import SwiftUI
import WebKit

enum B3ReadError: Error, Equatable {
    /// O token sumiu ou venceu (60 min, sem refresh): precisa entrar de novo.
    case session
    /// A B3 respondeu erro ou mudou o formato: a leitura fica pausada.
    case unavailable
}

/// Quem lê a posição na B3. O ViewModel depende só disto; o teste usa um falso.
@MainActor protocol B3Reader: AnyObject {
    /// Abre o site e chama `onLoggedIn` uma vez, quando a sessão da B3 aparecer.
    func start(onLoggedIn: @escaping @MainActor () -> Void)
    func read() async throws -> B3Read
}

// Única parte que conhece o site da B3 (validado em 30 out 2026). Se a B3 mudar login ou API, só este arquivo muda.
// A pessoa entra no site dentro da WebView; o app só lê `sessionStorage` depois do login e chama a mesma API
// que a página usa. O token nunca sai do aparelho e a senha nunca passa pelo app.
@MainActor final class B3Session: NSObject, B3Reader, WKScriptMessageHandler {
    static let site = URL(string: "https://www.investidor.b3.com.br/")!

    /// Criada a cada fluxo, já com a cena de pé. Criar no init do app (antes da janela) deixava os gestos
    /// da WebView sem ambiente e o primeiro toque derrubava o app (UIKit, _delayTouchesForEvent).
    private(set) var webView: WKWebView?
    private var onLoggedIn: (@MainActor () -> Void)?

    func start(onLoggedIn: @escaping @MainActor () -> Void) {
        self.onLoggedIn = onLoggedIn
        let config = WKWebViewConfiguration()
        // Mantém os cookies do login (Azure B2C) entre aberturas, para a B3 pedir menos vezes a senha.
        config.websiteDataStore = .default()
        config.userContentController.add(WeakMessageHandler(self), name: "fyin")
        config.userContentController.addUserScript(WKUserScript(source: Self.watchLogin, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.load(URLRequest(url: Self.site))
        webView = view
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.body as? String == "loggedIn", let callback = onLoggedIn else { return }
        onLoggedIn = nil
        callback()
    }

    func read() async throws -> B3Read {
        guard let webView else { throw B3ReadError.session }
        let value: Any?
        do {
            value = try await webView.callAsyncJavaScript(Self.readPositions, contentWorld: .page)
        } catch {
            throw "\(error)".contains("sessao") ? B3ReadError.session : B3ReadError.unavailable
        }
        struct Payload: Decodable { let referenceDate: String; let pages: [String] }
        guard let text = value as? String, let p = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8)), !p.pages.isEmpty else {
            throw B3ReadError.unavailable
        }
        return B3Read(referenceDate: p.referenceDate, pages: p.pages)
    }

    // A página guarda o token no sessionStorage depois do login; avisa o app uma vez.
    private static let watchLogin = """
    (function () {
      if (location.hostname.indexOf('investidor.b3.com.br') < 0) return;
      var t = setInterval(function () {
        if (sessionStorage.getItem('token')) { clearInterval(t); window.webkit.messageHandlers.fyin.postMessage('loggedIn'); }
      }, 500);
    })();
    """

    // Mesma API que a tela Minha carteira › Investimentos usa. Devolve as páginas cruas; quem interpreta é o backend.
    // shortcut: o dia de referência é a primeira data de "ultima-execucao" (ou ontem); trocar se a B3 expuser o campo com nome estável.
    private static let readPositions = """
    const tok = sessionStorage.getItem('token');
    if (!tok) throw new Error('sessao');
    const guid = encodeURIComponent(sessionStorage.getItem('cache-guid') || '');
    const headers = { Authorization: 'Bearer ' + tok, Accept: 'application/json' };
    const get = async (path) => {
      const r = await fetch('https://investidor.b3.com.br/' + path + (path.includes('?') ? '&' : '?') + 'cache-guid=' + guid, { headers });
      if (r.status === 401 || r.status === 403) throw new Error('sessao');
      if (!r.ok) throw new Error('http ' + r.status);
      return r.text();
    };
    let ref = null;
    try {
      const m = (await get('negocio-sistema/api/sistema/v1/carga/ultima-execucao')).match(/\\d{4}-\\d{2}-\\d{2}/);
      if (m) ref = m[0];
    } catch (e) { if (e.message === 'sessao') throw e; }
    if (!ref) ref = new Date(Date.now() - 864e5).toISOString().slice(0, 10);
    const pages = [];
    let page = 1, total = 1;
    do {
      const text = await get('negocio-posicao/api/extrato-posicao/v2/posicao?data=' + ref + '&pagina=' + page);
      pages.push(text);
      total = JSON.parse(text).totalPaginas || 1;
      page++;
    } while (page <= total && page <= 50);
    return JSON.stringify({ referenceDate: ref, pages });
    """
}

// WKUserContentController segura o handler com referência forte; o proxy evita o ciclo com a sessão.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Mostra a WebView do fluxo atual (criada em `start`).
struct B3WebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
