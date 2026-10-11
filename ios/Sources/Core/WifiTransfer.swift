import Foundation
import Network
import UIKit

/// Transfert Wi-Fi (comme VLC) : l'ordinateur ouvre une page dans son navigateur
/// et y dépose des musiques (ou des dossiers entiers), sans câble ni 3uTools.
final class WifiTransfer: ObservableObject {
    static let shared = WifiTransfer()
    static let port: UInt16 = 8080

    @Published private(set) var running = false
    @Published private(set) var address: String?
    @Published private(set) var receivedCount = 0
    @Published private(set) var current: String?
    @Published private(set) var error: String?

    /// Appelé quand des fichiers sont arrivés (la bibliothèque se met à jour).
    var onReceived: (() -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "music.wifi", qos: .userInitiated)
    private var refreshWork: DispatchWorkItem?

    static var targetFolder: URL {
        LibraryStore.importFolder
    }

    func start() {
        guard listener == nil else { return }
        error = nil
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: WifiTransfer.port) else { return }
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                TransferSession(connection: connection, owner: self).start(on: self.queue)
            }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.running = true
                        self?.address = WifiTransfer.wifiAddress().map { "http://\($0):\(WifiTransfer.port)" }
                    case .failed(let failure):
                        self?.error = failure.localizedDescription
                        self?.stop()
                    case .cancelled:
                        self?.running = false
                    default:
                        break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: queue)
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
        current = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    fileprivate func began(_ name: String) {
        DispatchQueue.main.async { self.current = name }
    }

    fileprivate func finished(_ name: String) {
        DispatchQueue.main.async {
            self.receivedCount += 1
            self.current = nil
            // Plusieurs fichiers d'affilée : on met la bibliothèque à jour une fois à la fin.
            self.refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onReceived?() }
            self.refreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    /// Adresse IPv4 du Wi-Fi (en0).
    static func wifiAddress() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var found: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            let interface = item.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || (found == nil && name.hasPrefix("en")) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        found = String(cString: host)
                        if name == "en0" { break }
                    }
                }
            }
            cursor = interface.ifa_next
        }
        return found
    }
}

/// Une connexion du navigateur de l'ordinateur : page d'envoi, ou réception d'un fichier.
private final class TransferSession {
    private let connection: NWConnection
    private weak var owner: WifiTransfer?
    private var header = Data()
    private var handle: FileHandle?
    private var target: URL?
    private var remaining = 0
    private var name = ""
    private var queue: DispatchQueue?
    private var keepAlive: TransferSession?

    init(connection: NWConnection, owner: WifiTransfer) {
        self.connection = connection
        self.owner = owner
    }

    func start(on queue: DispatchQueue) {
        self.queue = queue
        keepAlive = self
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.cleanup(success: false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveHeader()
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self = self else { return }
            if let data = data { self.header.append(data) }
            if let range = self.header.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: self.header[..<range.lowerBound], as: UTF8.self)
                let rest = self.header[range.upperBound...]
                self.handle(head: head, body: Data(rest))
            } else if complete || error != nil || self.header.count > 64 * 1024 {
                self.close()
            } else {
                self.receiveHeader()
            }
        }
    }

    private func handle(head: String, body: Data) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return close() }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let components = URLComponents(string: "http://music" + target)
        let path = components?.path ?? "/"

        if method == "GET" && (path == "/" || path == "/index.html") {
            respond(status: "200 OK", type: "text/html; charset=utf-8", body: Data(TransferPage.html.utf8))
        } else if (method == "PUT" || method == "POST") && path == "/upload" {
            let relative = components?.queryItems?.first(where: { $0.name == "path" })?.value ?? ""
            let length = Int(headers["content-length"] ?? "") ?? -1
            beginUpload(relative: relative, length: length, initial: body)
        } else if method == "OPTIONS" {
            respond(status: "204 No Content", type: "text/plain", body: Data())
        } else {
            respond(status: "404 Not Found", type: "text/plain", body: Data("Introuvable".utf8))
        }
    }

    /// Chemin sûr dans « Importés » (sous-dossiers gardés, jamais en dehors).
    private func safeURL(_ relative: String) -> URL? {
        let pieces = relative.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }
        guard let file = pieces.last else { return nil }
        let ext = (file as NSString).pathExtension.lowercased()
        guard audioExtensions.contains(ext) || ext == "lrc" else {
            return nil
        }
        var url = WifiTransfer.targetFolder
        for folder in pieces.dropLast() {
            url.appendPathComponent(folder, isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return LibraryStore.uniqueURL(url.appendingPathComponent(file))
    }

    private func beginUpload(relative: String, length: Int, initial: Data) {
        guard length >= 0 else {
            return respond(status: "411 Length Required", type: "text/plain", body: Data("Taille manquante".utf8))
        }
        guard let url = safeURL(relative) else {
            return respond(status: "415 Unsupported Media Type", type: "text/plain",
                           body: Data("Format non pris en charge".utf8))
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return respond(status: "500 Internal Server Error", type: "text/plain", body: Data("Écriture impossible".utf8))
        }
        self.handle = handle
        self.target = url
        self.name = url.lastPathComponent
        self.remaining = length
        owner?.began(name)
        write(initial)
    }

    private func write(_ data: Data) {
        if !data.isEmpty {
            let chunk = data.prefix(remaining)
            handle?.write(chunk)
            remaining -= chunk.count
        }
        if remaining <= 0 {
            try? handle?.close()
            handle = nil
            owner?.finished(name)
            target = nil
            respond(status: "200 OK", type: "application/json", body: Data("{\"ok\":true}".utf8))
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, complete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.write(data)
            } else if complete || error != nil {
                self.cleanup(success: false)
                self.close()
            } else {
                self.write(Data())
            }
        }
    }

    private func respond(status: String, type: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: GET, PUT, POST, OPTIONS\r\n"
        head += "Access-Control-Allow-Headers: Content-Type\r\n"
        head += "Connection: close\r\n\r\n"
        var packet = Data(head.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    /// Envoi interrompu : on retire le fichier incomplet.
    private func cleanup(success: Bool) {
        if !success, let url = target {
            try? handle?.close()
            handle = nil
            try? FileManager.default.removeItem(at: url)
            target = nil
        }
    }

    private func close() {
        connection.cancel()
        keepAlive = nil
    }
}

/// Page affichée dans le navigateur de l'ordinateur.
private enum TransferPage {
    static let html = #"""
<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Music – Transfert Wi-Fi</title>
<style>
:root{--brand:#ff2d60;--bg:#0f0f14;--card:#1b1b24;--text:#f4f4f8;--muted:#9a9ab0}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--text)}
main{max-width:760px;margin:0 auto;padding:32px 16px}
h1{margin:0 0 4px;font-size:28px}p{color:var(--muted);margin:0 0 20px}
#drop{border:2px dashed #3a3a4d;border-radius:18px;padding:40px 16px;text-align:center;background:var(--card);transition:.2s}
#drop.over{border-color:var(--brand);background:#3a1f28}
.buttons{display:flex;gap:10px;justify-content:center;flex-wrap:wrap;margin-top:16px}
label.btn{background:var(--brand);color:#fff;padding:12px 18px;border-radius:12px;cursor:pointer;font-weight:600}
label.btn.alt{background:#2b2b38}
input{display:none}
ul{list-style:none;padding:0;margin:20px 0 0}
li{background:var(--card);border-radius:12px;padding:12px 14px;margin-bottom:8px}
.name{display:flex;justify-content:space-between;gap:10px;font-size:14px}
.bar{height:6px;background:#2b2b38;border-radius:4px;margin-top:8px;overflow:hidden}
.bar div{height:100%;width:0;background:var(--brand);transition:width .2s}
.ok{color:#4cd964}.err{color:#ff5a5f}
</style></head>
<body><main>
<h1>Music · Transfert Wi-Fi</h1>
<p>Glissez ici vos musiques (MP3, M4A, FLAC, WAV…), leurs paroles .lrc ou un dossier entier (un album). Gardez Music ouvert sur l'iPhone pendant l'envoi.</p>
<div id="drop">
  <div style="font-size:42px">⬆︎</div>
  <div>Déposez des fichiers ou des dossiers ici</div>
  <div class="buttons">
    <label class="btn">Choisir des fichiers<input id="files" type="file" multiple></label>
    <label class="btn alt">Choisir un dossier<input id="folder" type="file" webkitdirectory multiple></label>
  </div>
</div>
<ul id="list"></ul>
</main>
<script>
const okExt=/\.(m4a|mp3|aac|wav|flac|aif|aiff|caf|m4b|alac|lrc)$/i;
const list=document.getElementById('list');let queue=[];let busy=false;
function add(file,path){if(!okExt.test(file.name))return;const li=document.createElement('li');
li.innerHTML='<div class="name"><span></span><span class="st">En attente</span></div><div class="bar"><div></div></div>';
li.querySelector('span').textContent=path||file.name;list.appendChild(li);queue.push({file,path:path||file.name,li});next();}
function next(){if(busy||!queue.length)return;busy=true;const job=queue.shift();const xhr=new XMLHttpRequest();
const st=job.li.querySelector('.st'),bar=job.li.querySelector('.bar div');
xhr.open('PUT','/upload?path='+encodeURIComponent(job.path));
xhr.upload.onprogress=e=>{if(e.lengthComputable){const p=Math.round(e.loaded/e.total*100);bar.style.width=p+'%';st.textContent=p+' %';}};
xhr.onload=()=>{if(xhr.status==200){st.textContent='Envoyé';st.className='st ok';bar.style.width='100%';}else{st.textContent='Refusé ('+xhr.status+')';st.className='st err';}busy=false;next();};
xhr.onerror=()=>{st.textContent='Échec (Music fermé ?)';st.className='st err';busy=false;next();};
xhr.send(job.file);}
document.getElementById('files').onchange=e=>{for(const f of e.target.files)add(f);e.target.value='';};
document.getElementById('folder').onchange=e=>{for(const f of e.target.files)add(f,f.webkitRelativePath);e.target.value='';};
const drop=document.getElementById('drop');
drop.ondragover=e=>{e.preventDefault();drop.classList.add('over');};
drop.ondragleave=()=>drop.classList.remove('over');
function walk(entry,prefix){if(entry.isFile){entry.file(f=>add(f,prefix+f.name));}
else if(entry.isDirectory){const r=entry.createReader();const read=()=>r.readEntries(es=>{if(!es.length)return;es.forEach(x=>walk(x,prefix+entry.name+'/'));read();});read();}}
drop.ondrop=e=>{e.preventDefault();drop.classList.remove('over');const items=e.dataTransfer.items;
if(items&&items.length&&items[0].webkitGetAsEntry){for(const it of items){const en=it.webkitGetAsEntry();if(en)walk(en,'');}}
else{for(const f of e.dataTransfer.files)add(f);}};
</script></body></html>
"""#
}
