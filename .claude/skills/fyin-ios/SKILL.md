---
name: fyin-ios
description: Arquitetura e convenções do app iOS do Fyin (SwiftUI, ios/Fyin). Use ao criar ou alterar tela, ViewModel, Repository, modelo de API, componente do design system, animação ou ao consumir um endpoint novo do backend.
---

# App iOS do Fyin

SwiftUI, iOS 26, Swift concurrency, `@Observable`. **Sem dependências de terceiros**; use só SDK da Apple.

## Estrutura

```
ios/Fyin/
  App/FyinApp.swift        raiz de composição: única que monta dependências reais
  Core/                    APIClient, Money: infraestrutura sem tela
  DesignSystem/            Theme (cores qXxx, Font.urbanist, Motion), componentes visuais reutilizáveis
  Features/<Nome>/         <Nome>View, <Nome>ViewModel, <Nome>Repository, modelo(s) da API
```

Uma pasta por feature. Feature não importa outra feature: a ligação entre elas (ex.: terminou o sync → a home recarrega) é um closure injetado em `FyinApp`.

## Camadas

- **Model**: `struct … : Decodable, Equatable, Sendable`, espelho do JSON do backend (skill `fyin-api`). Regra de exibição derivada (percentual, rótulo) vive em `extension` do modelo.
- **Repository**: `protocol XRepository: Sendable` + `LiveXRepository(api: APIClient)` + `PreviewXRepository` com dados fixos para `#Preview`. Só traduz chamada HTTP em modelo; sem estado, sem lógica.
- **ViewModel**: `@MainActor @Observable final class`, recebe o `Repository` (protocolo) no `init`. Guarda estado (`private(set)`), cache e decisão de carregar/falhar. Sem import de SwiftUI.
- **View**: recebe o ViewModel por parâmetro (`let model`), sem `@StateObject`. Sem rede, sem regra. Dispara carga com `.task(id:)`.
- **Composição**: `FyinApp.init` cria `APIClient`, repositories e ViewModels. Nenhum singleton.

## Regras

- **Dinheiro**: sempre `Money` (`Decimal` decodificado de texto). Nunca `Double`/`Float`, nem para percentual: converta o `Decimal` só no ponto final de exibição.
- **Datas da API**: `Date` para instantes (decoder do `APIClient` já aceita RFC 3339 com/sem fração); dia de calendário e mês ficam `String` (`YYYY-MM-DD`, `YYYY-MM`) e são formatados em GMT/pt_BR (`MonthLabel`). O servidor decide o mês atual; o app não calcula.
- **Rede**: tudo passa por `APIClient.get/post`. Endpoint novo = método no Repository da feature. Não use `URLSession` direto.
- **Erros**: ViewModel converte em estado (`failed`), não propaga a exceção para a View. Cancelamento (`CancellationError`, `URLError.cancelled`) não é falha.
- **Visual**: só tokens de `Theme.swift` (`Color.q*`, `Font.urbanist`, `Motion`), que espelham o `Fyin.pen`. Sem hex ou duração solta na View. Tela nova parte do frame correspondente no `Fyin.pen`.
- **Movimento**: use `Motion.standard/enter`; respeite `accessibilityReduceMotion`; feedback tátil com `.sensoryFeedback`.
- **Acessibilidade**: Dynamic Type (`urbanist`, não `urbanistFixed`, salvo exceção justificada), rótulos VoiceOver em elementos sem texto.
- **Texto da UI** em português (pt-BR), caixa de frase.
- **Segredos**: `Secrets.swift` fica fora do git (modelo em `ios/Secrets.swift.example`). Nunca versionar token.
- Comentários em português, só o porquê. Atalho consciente: `// shortcut: <limite>, <quando trocar>`.

## Tela nova, checklist

1. Modelo `Decodable` batendo com o JSON (confira o handler Go).
2. `Repository` (protocolo + Live + Preview).
3. `ViewModel` testável com um `Repository` falso.
4. `View` só com tokens do design system + `#Preview` usando o `Preview…Repository`.
5. Montagem em `FyinApp`.
6. Se o ViewModel tem lógica (estado, cache, derivação), teste unitário com `Repository` falso (Swift Testing).

## Verificação

```bash
xcodebuild -project ios/Fyin.xcodeproj -scheme Fyin -destination 'generic/platform=iOS Simulator' build
```

Para ver rodando no Simulator, use a skill `run`. Backend local: `make up && make api`.
