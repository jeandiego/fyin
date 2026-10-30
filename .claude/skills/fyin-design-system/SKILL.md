---
name: fyin-design-system
description: Qual componente, token ou padrão do design system do Fyin usar (e qual NÃO usar) ao montar tela, card, lista, filtro, alerta, estado vazio/erro, animação ou mascote. Use antes de qualquer UI nova; evita reabrir o Fyin.pen. Resumo do Fyin.pen (frames DS · 00 a 03).
---

# Design system do Fyin

Fonte: `Fyin.pen`. Mapa: seção 1 DS · 00 a 03 (fundamentos, componentes, padrões, mascote) · seção 2 telas · seção 3 estados 09 vazios, 10 carregamento, 11 dados financeiros, 12 conexão · seção 4 comportamento 13 movimento, 14 Início no iOS, 15 Ajustes, 16 patrimônio morph. O quadro mais específico/recente (14, 16) vale sobre o DS quando divergem. Este arquivo é o resumo para decidir **qual peça usar**. Só abra o `.pen` para medidas finas ou componente que não esteja aqui. Código: `ios/Fyin/DesignSystem/Theme.swift` (tokens `q*`, `Motion`), `SegmentedSwitch`, `SlotText`, `Institutions`. Skill de arquitetura iOS: `fyin-ios`.

## Princípios (valem para tudo)

- Branco, cinza quente, **um** acento lime. Neutros são 95% da tela; o acento marca o que está ativo ou positivo, nunca decora.
- Profundidade por cor, não por sombra. Sombra só no que flutua (tab bar, toast, sheet).
- **Uma ação primária por card.** Rótulo nomeia a ação ("Reconectar Nubank"), nunca "OK".
- Texto em pt-BR, caixa de frase. Sem maiúsculas, sem rótulo-sobrelinha, sem emoji.
- Cor nunca carrega o significado sozinha: sempre texto junto.
- Sem token = sem valor. Nada de hex, raio, espaço ou duração solta na View.

## Tokens

| Uso | Token |
| --- | --- |
| Fundo de tela / card / trilha / borda | `q/bg` / `q/card` / `q/soft` / `q/line` |
| Texto / apoio / rótulo / centavos e desabilitado | `q/ink` / `q/text-2` / `q/text-3` / `q/ghost` |
| Acento (selecionado sobre escuro, CTA no herói) | `q/accent` (`q/accent-soft` = fundo de ícone de insight) |
| Saudável | `q/ok`, `q/ok-ink`, `q/ok-tint` |
| Atenção (ação com prazo) | `q/attn-ink`, `q/attn-tint`, `q/attn-bg`, `q/warn` |
| Acima do limite | texto `q/over-ink`; `q/over` só como brilho/ícone |
| Informação neutra | `q/info-ink`, `q/info-tint` (nunca para valores) |
| Sobre o card escuro | `q/on-dark`, `-2` (55%), `-3` (30%), `-line`, `q/skeleton-dark` |

**Nada é vermelho.** Acima do limite é coral, sempre com texto explicando. Brilho (`glow/ok|over|attn`) só no Spending Card e estados financeiros; nunca pulsa.

**Tipografia** (Urbanist): número grande em Light 300, texto em Medium 500, título em SemiBold 600. Centavos e unidade sempre em `q/ghost`. Valores em lista: algarismos tabulares.
`display/hero` 84 saldo do herói · `display/metric` 56 percentual · `title/large` 28 título de tela · `value/medium` 24 valor em card · `value/small` 22 valor secundário · `title/card` 17 título de estado/alerta · `body` 15 · `body/small` 14 · `caption` 13 · `micro` 12 · `tab` 10.

**Espaço** (base 4): 8 entre cards e chips · 12 tela↔borda · 16 card compacto · 20 padding de card e de tela · 24 entre grupos · 32 entre seções · 48 respiro de vazio.
**Raios**: 6 skeleton · 10 stat · 14 campo/bloco interno · 18 card · 28 Card/Group · 43 topo do herói · 999 botão, pill, chip. Toque mínimo 44×44pt.
**Ícones**: Phosphor Regular no design ↔ SF Symbol no iOS. Traço único, preenchido só no estado ativo. `sparkle` é exclusivo de insight.

## Escolha rápida: preciso de…

| Preciso de… | Use | NÃO use |
| --- | --- | --- |
| Trocar de seção | Tab Bar | Segmented Control |
| Detalhe de algo tocado | Pilha (push) + Nav Header | Sheet |
| Tarefa curta (definir limite, conectar banco) | Sheet | Tela cheia |
| Mostrar um número | Amount / Metric Card / Stat Tile | Texto solto sem ghost nos centavos |
| Agrupar linhas | Card / Group | Um card por linha |
| Lista de transações / categorias | Transaction Row, Category Row dentro de Card / Group | Divisórias entre linhas |
| Avisar algo | Alert (atenção/sucesso/info) | Modal |
| Confirmar que algo foi feito | Toast com Desfazer | Sheet |
| Confirmar algo irreversível | Confirmation Sheet | Toast |
| Data velha / frescor | Inline Status | Alert |
| Falha pontual | Inline Error junto ao elemento | Alert global |
| Carregando | Skeleton com a forma do conteúdo | Spinner (exceto dentro de botão) |

## Componentes: quando usar / quando não usar

### Navegação
**Tab Bar** (+ Tab Item / Ativo; iPad = Navigation Rail). Usar: 4 seções de topo (Início, Projeção, Transações, Insights). Não usar: filtrar dado, ação (busca é global, fora das abas). Ativo = escuro + ícone preenchido; pílula desliza 240ms.
**Nav Header**. Usar: telas empilhadas (Voltar, título grande que colapsa, uma ação à direita). Não usar: na raiz de uma aba.
**Sheet**. Usar: tarefa curta e autocontida, um campo, um botão. Arrastar fecha = cancela. Não usar: detalhe (isso é push).

### Botões
**Button / Primary**: ação principal do contexto. Uma por card. Não usar: duas primárias juntas.
**Button / Secondary**: alternativa ("Depois", "Ver outubro"). Não usar: como única ação importante.
**Button / Accent**: só sobre o card escuro. Não usar: sobre fundo claro.
**Button / Text**: links em texto e rodapés. Não usar: como CTA.
**Icon Button** (claro / escuro): ação de ícone com toque 44pt. Não usar: sem `accessibilityLabel`.

### Cards
**Card** (com slot): contêiner padrão, `q/card`, raio 18, sem sombra, 8pt entre cards. Não usar: aninhar card em card; envolver tudo em card sem função.
**Card / Group**: agrupa linhas, raio 28, sem divisórias. Não usar: para um valor ou gráfico.
**Card / Hero**: saldo, escuro, **uma vez por tela**, no topo, inclui a status bar. Botões nele: Accent ou On Dark. Não usar: segundo herói, ou abaixo do topo. No iOS (quadro 14, vale sobre o DS) o herói encosta no topo e nas laterais, só a base tem raio 28, cards abaixo a 12 de margem; o raio 43 do DS · 01 está obsoleto.

### Métricas
**Amount**: R$ e centavos em ghost, tabular. Base de todo valor monetário.
**Spending Card**: gasto vs limite com brilho pelo ritmo (saudável/acima). Não usar: para outra métrica.
**Metric Card**: par lado a lado (8pt) com rótulo, valor e contexto com período. Não usar: sozinho sem contexto/período.
**Stat Tile**: número + unidade pequena (ex.: transações). Não usar: valor monetário principal.

### Projeção
**Forecast Chip** (4 estados): diz se o mês fecha bem. Sempre texto + cor.
**Forecast Note**: uma linha no rodapé de card de gasto/projeção: um número + uma causa. Não usar: texto longo.
**Progress Track / Data Progress**: proporção; cor do Fill segue o significado (ink, ok, over). Não usar: como gráfico principal.

### Gráficos
**Chart / Projeção**: barras acumuladas por dia; realizado em ink, projetado em ghost, limite = única linha coral.
**Chart / Comparação**: período atual vs média.
**Chart / Categorias**: participação em tons de ink.
Não usar: pizza, linha decorativa, arco-íris, eixos numéricos (o valor importante vem escrito).

### Insights
**Insight Row**: linha compacta na Início, uma frase com número e direção.
**Insight Card / Expandido** (e Completo): mostra o cálculo; ação opcional. Não usar: `sparkle` fora de insight.

### Linhas (sempre dentro de Card / Group, altura 64)
**Transaction Row** + **Day Header**: transação; entrada em `q/ok` com "+"; sem categoria = ícone question + "Sem categoria". Transação abre detalhe, não outra lista.
**Category Row**: participação com barra fina; delta só se ±5% (acima `over-ink`, abaixo `ok`).
**Bank Row / Bank Avatar**: banco por cor e iniciais (`Institutions`). Não usar: logo desenhado.
**Settings Row**, **Section Label**: itens e títulos de seção em Ajustes.

### Filtros e seleção
**Filter Pill** (+ Ativo): filtra por pessoa; um por vez, sem multisseleção.
**Filter Chip**: filtro ativo removível, fora da vista. Não usar: para escolher filtro (use Pill).
**Month Pill Row**: período no herói escuro, até 3 meses, rola horizontal. Não usar: fora do herói.
**Segmented Control** (claro): 2–4 visões do mesmo dado em fundo claro (Dia/Semana/Mês, Gastos/Entradas). `Picker(.segmented)`. Não usar: seção do app (Tab Bar) ou pessoa/período.
**Segmented Control / Escuro** = `SegmentedSwitch`: 2–4 visões do mesmo dado no herói ou modal escuro (ex.: R$ | US$ no detalhe da corretora). Não usar: fundo claro; pessoa/período.

### Campos
**Text Field**: rótulo sempre visível acima; erro diz problema + saída em `over-ink`, sem tremer. **Currency Field**: valor monetário, teclado numérico, formatado ao vivo. **Search Field**: busca. **Toggle Row**: liga/desliga (Toggle nativo tingido `q/ok`). Não usar: placeholder no lugar do rótulo.

### Contas
**Account Card**: banco + saldo + rodapé de estado (sincronizando, expirada com botão Renovar). **Sync Hero**: topo de Ajustes com status e sincronizar. Não usar: erro técnico; diga o que falta fazer.

### Feedback
**Alert / Atenção**: ação + prazo, fundo âmbar claro, um por vez no topo da Início, "Depois" recolhe. **Alert / Sucesso**: some em 4s. **Alert / Informação**: fica enquanto a condição existir. Nunca modal.
**Toast** (quadro 19, `msYJe`; código `DesignSystem/Toast/`): ver a seção "Toast" abaixo.
**Inline Status**: frescor ("Atualizado há 5 min").
**Push Notification**: só prazo e mudança relevante, máx. 1/dia; valores só se permitido em Ajustes.
**Skeleton** (Linha/Bloco/Círculo/Row/Card): forma exata do conteúdo, shimmer 1.6s, estático com Reduzir movimento. Escuro: `q/skeleton-dark`.

### Estados vazios e de erro
**Empty State**: motivo + um próximo passo, mantém a forma do card. Não usar: duas ações.
**Error State**: título neutro ("Pausada", nunca "Erro") + causa + impacto + ação; dado salvo nunca some.
**Inline Error**: junto ao elemento que falhou. **Retry Row**: no lugar do conteúdo que não carregou.
**Confirmation Sheet**: só irreversível (desconectar, apagar meta), com a consequência em números; botão com o verbo; cancelar embaixo e "mantém o estado". Nunca vermelho. Não usar: ação reversível (Toast + Desfazer).

### Mascote Fy
Componentes `Fy / Neutro | Piscando | Feliz | Pensando | Atento | Offline`. Escolha pelo dado: Feliz só meta batida/mês no azul, Atento só alerta real, Pensando = IA/carregando, Offline = sem conexão. Usar: splash, cabeçalho de insights, vazio e erro; sobre tinta `#161616`. Não usar: decoração repetida em lista/card/botão; boca, braços, brilho, gradiente, sombra; trocar cores (só Offline desbota). Mín. 29pt; abaixo disso, ícone do app.

## Padrões de interação

- **Três níveis, nunca misturados**: aba = seção; pilha = detalhe; sheet = tarefa.
- **Filtro** muda o recorte, não o lugar. Pessoa filtra a tela inteira, inclusive totais. Sem resultado = Empty State citando o filtro + saída ("Ver todos da casa"). Resposta ≤300ms troca direta; mais que isso, skeleton.
- **Drill-down**: quanto → onde → em quê, máx. 3 níveis até a transação. O valor tocado viaja ao próximo nível (shared element 320ms). Voltar preserva rolagem e filtro.
- **Troca de visão**: período no herói (Month Pill Row), granularidade no Segmented Control. Mês anterior entra pela esquerda, próximo pela direita (12px + fade 400ms). Valores mudam por crossfade por dígito, não contagem rolante (exceção: `SlotText` onde o produto já usa rolo).
- **Carregamento**: 0–300ms nada · 300ms–2s skeleton (dado antigo fica) · 2–8s skeleton + Inline Status com números reais · >8s libera o app e avisa ao terminar. Falha mantém o último dado com a hora.
- **Erro**: causa em português (nunca código), preserva dado, depois de resolver volta à mesma tela.
- **Confirmação**: reversível → executa + Toast Desfazer. Irreversível → Confirmation Sheet. Sempre termina com o resultado visível no lugar.

## Toast (quadro 19)

Uma anatomia só: ícone ou atividade → mensagem + descrição → ação → fechar; progresso embaixo. Slots ausentes não ocupam espaço. Uma instância muda de estado (carregando → progresso → resultado), não há componente de loading nem de progresso. Código: `Toast` + `ToastCenter` (regra, sem SwiftUI), `ToastView`/`ToastStack`, `.toastHost` aplicado uma vez no `FyinApp`. Quem dispara usa `@Environment(ToastCenter.self).show(Toast(id:, title:, …))`. Nunca desenhe toast na feature.

**Usar**
- Confirmar o resultado de uma ação direta ("Categoria alterada para Mercado" + Desfazer), reversível e sem trocar de tela.
- Resultado que chega depois de alguns segundos (B3 concluída, sincronização por botão).
- Falha recuperável que não apaga dado, com uma saída ("Tentar novamente"). O dado salvo continua visível.
- Tarefa longa em segundo plano: carregando, ou progresso só com total conhecido.

**Não usar**
- Irreversível (desconectar, apagar): Confirmation Sheet. Toast não confirma o que não dá para desfazer.
- Erro que exige intervenção: continua na origem (Inline Error, Alert, Account Card). O Toast só informa e oferece saída; nunca prende a pessoa nele.
- Condição que persiste ou prazo (fatura vencendo, autorização expirando): Alert / Atenção ou Inline Status.
- Navegar: tocar no corpo não navega; a ação nomeia o destino.
- Texto longo ou tela rolável dentro do Toast. Se passar de ~40% da área útil: resumo + "Ver detalhes" e o texto completo na origem.
- CPF, credenciais, códigos técnicos, percentual sem denominador real (B3 usa etapas, nunca % inventada).
- Vermelho saturado ou fundo colorido para erro.

**Composições e prazos** (o prazo é derivado da composição; `Toast.lifetime` só para exceção documentada)

| Composição | Prazo | Observação |
| --- | --- | --- |
| Compacto (só mensagem) | 3 s | confirmação sem ação |
| Expandido (com descrição) | 6 s | falha recuperável |
| Ação (ex.: Renovar) | 8 s, ou persistente | persistente se exige intervenção; mostra o fechar |
| Desfazer | 5 s | só quando a reversão é suportada; a janela é real |
| Carregando / Progresso | 8 s na frente | depois some da frente; o status fica na origem e a tarefa segue |
| Exceção B3 | 5 s | `lifetime: .seconds(5)` |

**Semântica** (superfície escura): sucesso `q/accent` · erro `q/over-tint` · atenção `q/attn-tint` · informação `q/info-tint`. Superfície `q/ink`, texto `q/on-dark`, apoio `q/on-dark-2`, ação `q/accent` sobre branco a 10%. Raio 28, sombra `q/shadow` (y 8, blur 24). 362 pt em iPhone de 402 (margem 20, máx. 420), altura 60 compacta. Sobre fundo escuro o Toast é claro (`q/bg` + `q/ink`): só entra com o toast de topo.

**Posição pela origem, não pela semântica**: ação direta e resultado da ação → `bottomCenter` (12 pt acima da safe area, teclado ou tab bar). Evento automático e atualização não solicitada → `topCenter`. A origem registrada no início acompanha a operação até o resultado.

**Pilha (decisão posterior ao board; o quadro 19 diz "não empilhar", isto vale sobre ele)**
- Vários Toasts ao mesmo tempo formam uma pilha na base: o mais novo na frente, até 3 visíveis, os anteriores espiando atrás (10 pt, escala 0,95 por nível, conteúdo oculto).
- Tocar na pilha abre todos, cada um com o seu fechar e swipe. Abrir pausa os prazos; recolhe sozinha em 4 s ou ao tocar de novo.
- Dispensar um (swipe para baixo 44 pt ou fechar) não afeta os outros. A frente nunca cobre um Desfazer sem que ele continue ao alcance dentro da pilha.
- Mesmo `id` atualiza no lugar. Fila total de 5 (visíveis + espera, FIFO): ao exceder, cai o informativo mais antigo da espera; Toast com ação não é descartado.

**Acessibilidade**: anuncia mensagem + descrição uma vez, sem roubar o foco; ordem mensagem → descrição → ação → fechar; fechar com rótulo "Dispensar notificação" e ação de acessibilidade equivalente. Foco do VoiceOver pausa o prazo; com VoiceOver o mínimo é 8 s (compacto) e 12 s (descrição ou ação). Dynamic Type de acessibilidade reflui ícone, texto e ação na vertical, ação em largura total. Reduzir Movimento: crossfade, sem deslocamento nem escala; atividade vira símbolo estático.

**Movimento (base)**: entrada +12 → 0 pt, opacidade e escala 0,98 → 1, `Motion.spring(Motion.considered)` sem bounce. Overlay não muda o layout nem bloqueia toque no resto da tela.

**Pendente (não implementado)**
- **Toast de topo e morph.** Entra quando existir o primeiro toast de evento automático (sync agendado, autorização expirada). A cápsula nasce abaixo da safe area (y 70), largura, altura e raio crescem em 320 ms, o conteúdo revela nos últimos 160 ms, a saída leva 240 ms com opacidade primeiro; nunca um banner deslizando de cima. Junto vem a superfície clara, a fila única entre topo e base e a validação em dispositivo.
- Apresentar acima de uma sheet (hoje o host fica na raiz, abaixo das sheets): transferir a mesma instância, nunca duplicar.
- Prazo retomado: ao pausar/retomar o prazo recomeça inteiro. Descartar da espera o informativo com mais de 30 s.
- `Fyin.pen` quadro 19 ainda diz "não empilhar"; atualizar o quadro com a pilha.

## Estados por situação (quadros 09 a 12)

Todo card/tela cobre: vazio, carregando, parcial, erro. Mantém a forma do card final, uma única ação, texto com causa e saída. Nunca ilustração, culpa ou "Erro".

| Situação | Mostrar |
| --- | --- |
| Sem conta conectada | Card de saldo escuro com `R$ 0,00`, motivo, botão Conectar conta, garantia (somente leitura, Open Finance) |
| Mês sem transação | Empty State + "Ver outubro" + hora da última verificação (não pode parecer erro) |
| Poucos dados para insight/projeção | Card com progresso ("12 de 21 dias", "Pronta em 14 nov"): conta quanto falta, não mostra erro. Sem projeção > projeção errada |
| Sem meta | Spending Card funciona sem meta; sugere limite calculado ("Definir limite"), nunca impõe |
| Busca/filtro sem resultado | Repete o termo, diz onde buscou, oferece 2 saídas ("Limpar filtros", "Buscar em tudo") |
| Mês com dados parciais | Selo "Desde 14 out" junto ao card; percentual real |
| Renda não encontrada | Card atenção com 2 saídas ("Informar valor", "Minha renda varia"); projeção usa só gastos |
| Transação sem categoria | Chips "Parece com:" com sugestões; toque aplica + Toast Desfazer |
| Projeção sem um banco | "Pausada por enquanto" + causa + impacto (~30%) + Reconectar |
| Gasto acima do ritmo | Mesmo card, brilho coral suave, texto compara com o ritmo e aponta a causa, sem julgar |
| Mês saudável | Verde confirma, não comemora; folga + motivo, sem confete |
| Fatura vencendo | Alert / Atenção dispensável com ação, prazo e o que tranquiliza (saldo cobre) |
| Conectando banco | Etapas nomeadas reais (autorização, contas, histórico), sem % inventada |
| Conectado | Resumo com números (contas, cartão, transações) + "Ver meu painel" |
| Sincronizando | Valores antigos ficam; linha "Sincronizando N de M" nomeia o banco; barra fina 3pt |
| Sync parcial | Lista o que funcionou, total explica de onde vem o valor pendente |
| Autorização expirou | Rotina do Open Finance, não problema: "Renovar autorização", histórico garantido |
| Banco fora do ar | Falha é do banco: tenta sozinho, "Tentar agora" opcional, valores com a hora |
| Acesso perdido (senha) | Diz quanto leva (~1 min), "Reconectar" + "Agora não" |
| Servidor do Fyin fora | Distinto de erro de banco: sync desligado, dado salvo visível, nova tentativa ao voltar a rede |

Carregamento por tempo (não por tela): 0–300ms nada · 300ms–2s skeleton · 2–8s skeleton + linha dizendo o quê · >8s libera o app · falha mantém o último dado com a hora. Skeleton: shimmer diagonal 1.6s linear só nos blocos; Reduzir movimento = estático a 60%. "Gerando insight": ícone pulsa 0.6↔1 a cada 1.2s por no máx. 8s, sem barra falsa.

## Fluxos de Ajustes e sincronização (quadro 15)

- Entrada: engrenagem no herói da Início. Ajustes: **Sync Hero** (última sincronização + "Sincronizar tudo"), **Bank Row** por conta (dono + horário), Settings Row para Regras de gasto, Divergências e Patrimônio manual.
- Sync: um por banco por vez; botão vira progresso e não aceita outro toque; sem cancelar; >2 min "Está demorando. Pode sair". O dado visível só muda após o import completo; erro nunca apaga nada. Concluído = Toast 3s + háptico de sucesso.
- Estado do banco → tom → ação: UPDATED (em dia, abre detalhe) · UPDATING/Importando (neutro, sem ação) · LOGIN_ERROR, WAITING_USER_INPUT, OUTDATED, consentimento ≤30 dias (atenção, 1 ação) · consentimento vencido (erro, reconectar) · servidor fora (neutro, tentar agora).
- Reconectar/Renovar abre o Pluggy Connect em Sheet explicando antes de sair; volta e sincroniza só aquele banco. Desconectar = Confirmation Sheet (único primário, diz o que some e o que fica).
- Divergência: "Informado × Calculado × Diferença" + o remédio (ver transações ou ajustar a regra).
- Regras de gasto: um toggle por categoria; mostra o efeito no mês antes de gravar. Patrimônio manual: Sheet curto (nome + valor, teclado numérico, botão só liga com os dois).
- VoiceOver anuncia "Sincronizando, 1 de 3 prontos". CPF/documento nunca chegam ao app.

## Fontes fora do Open Finance (quadro 18, B3)

- Em Ajustes, seção "Fora do Open Finance" abaixo das contas: uma linha por dono importado ("B3 · Tesouro e ações", dono + hora + títulos) e "Importar da B3". Nunca misturar com os bancos: não sincroniza sozinha.
- Desatualizada (>30 dias, decidido pelo servidor): selo "Atualizar" em `q/attn-tint`/`q/attn-ink`, sem push diário.
- Sheet curta antes de sair: o que acontece em 3 passos, quem guarda a senha, seletor de dono (pílulas), "Entrar na B3" + "Agora não". Fundo sólido `q/bg` (não o vidro do sistema).
- Site de terceiro em WebView: sheet grande com barra (fechar, título, cadeado + domínio real) e faixa do Fyin acima do site (`q/info-tint` "O Fyin lê só a sua posição", `q/ok-tint` depois do login, `q/attn-tint` se pausar). **O Fyin nunca desenha o site.**
- Leitura: painel flutuante com etapas reais (entrou → lendo posição → enviando ao Fyin), sem porcentagem. Falha: "Pausada por enquanto" + causa + "Entrar de novo"; a posição salva nunca some.
- Derivativo (futuro, opção): aparece no detalhe do patrimônio com "fora do total", sem peso nem barra.

## Modal que se transforma (quadro 16, patrimônio investido)

Uma só superfície com estado `.home | .contas(filtro) | .detalhe(conta)`; nunca sheet sobre sheet. A linha do Card / Hero vira o modal (raio concêntrico ao aparelho: 55 − 12 = 43), ancorado na base a 12pt. Use para: abrir detalhe de uma linha do herói sem navegar. Não use: para tarefa de formulário (Sheet) ou drill-down de 3 níveis (pilha).
- Molas sem bounce: `.spring(duration: 0.32, bounce: 0)` abrir e entrar no detalhe; 0.28 filtro e voltar; 0.24 fechar. `matchedGeometryEffect` ids `"patrimonio"` e `conta.id`. Interrompível: retoma do retângulo atual. Reduce Motion: só crossfade.
- Filtro Todos | Jean | Marina: base presa, só o topo muda. Conteúdo >800pt rola dentro do modal com fade 16pt topo / 28pt base.
- Dados: cada conta é (instituição, titular), Nubank de Jean e de Marina nunca somam. Detalhe agrupa por tipo com subtotal e peso (Caixinhas, CDB, LCI/LCA, Ações, ETFs...). Dólar: valor em R$ no total, US$ só como referência; seletor R$ | US$ (`SegmentedSwitch`) só com cotação PTAX.

## Números em rolo (`SlotText`)

Usar em valores que mudam por ação do usuário (mês, período, filtro) e na Home: saldo, patrimônio, gastos, cartão, empréstimos. Cada dígito é um rolo; "R$", "." e "," ficam parados; rolos casados pelo fim do número. 1º rolo 900ms, 70ms entre rolos esq→dir, 1 volta extra, ease-out quártico, sem overshoot, direção segue o número. Enquanto o valor carrega, o atual fica. Não usar: valor que muda várias vezes por segundo (troca direta), textos e datas (crossfade). Reduzir movimento: troca instantânea. Todos os números de uma tela usam os mesmos parâmetros.

## Movimento

`motion/instant` 100 toque · `quick` 160 ícone/cor · `base` 240 valores/estado · `considered` 320 expandir/sheet · `screen` 400 tela/visão. Curva padrão (0.2,0,0,1), entrada (0.16,1,0.3,1), saída a 70%. Deslocamento 4/8/12–16px; escala nunca acima de 2%. Reduzir movimento: remove deslocamento e rotação, mantém opacidade e cor. Use `Motion.*` do `Theme.swift`.

## Checklist antes de entregar tela

1. Cada peça vem da tabela acima; se nada serve, **pergunte antes de inventar** (e crie o componente no `.pen` no mesmo PR).
2. Só tokens `q/*` e `Motion`; um herói, uma primária por card.
3. Estados cobertos: carregando (skeleton), vazio, erro, dado velho.
4. Cor + texto; toque ≥44pt; Dynamic Type; rótulo VoiceOver em ícone sem texto; Reduzir movimento.
5. Se o `.pen` e esta skill divergirem, corrija a skill no mesmo PR.
