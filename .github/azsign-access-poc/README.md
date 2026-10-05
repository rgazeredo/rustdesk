# APK PoC — não distribuir em produção

Base: tag RustDesk 1.4.9 + patches AZSign. Incremento v18 na branch
`feat/azsign-access-pilot`, PR #1. O workflow mantém a assinatura existente
e a chave **pública** do laboratório. Não é release geral nem troca automática
do servidor atual. Nenhuma chave privada entra no build.

## Provisionamento

Protocolo 2 do provider `com.carriez.flutter_hbb.azsign.accesspoc`: somente
UID shell/root, via `content call`. `prepare-identity` recebe UUID emitido pelo
CMS e gera RSA-2048 no Android; devolve somente CSR DER base64, com CN=UUID.
Retry preserva a chave. Outra identidade é recusada, sem substituir a existente.
`activate` recebe CA/certificado DER base64 e profile JSON base64, valida
assinatura, validade, CN, public key, CA:FALSE/clientAuth antes de publicar
`active.json` atomicamente. Não importa nem exporta chave privada.
Arquivo de chave fica no diretório privado `azsign-access-poc/identity/key.der`,
modo 0600; backup Android desabilitado. Usuário Android 0; outros perfis não
homologados. Geração usa JCA e CSR Bouncy Castle 1.86 jdk15to18 (versão fixa).
Documentação: https://www.bouncycastle.org/documentation/documentation-java/

Atualizar v17 para v18 exige novo provisionamento: arquivos importados no
protocolo antigo NÃO são fallback no Android. Senha/ID/input não são apagados.
`identity.test.mjs` valida CSR real com OpenSSL, repetição, permissão de arquivo,
recusa de outra identidade/chave e de certificado serverAuth. Compila provider
com Android jar quando ANDROID_TEST_JAR é informado. Isso não substitui o teste
no Android nem comprova proteção hardware/anti-clonagem.

O profile contém host, nome TLS e portas separadas para registration,
rendezvous e relay. Configuração ausente/inválida causa falha fechada.
No laboratório do DC400, ADB reverse liga as portas 32116–32118 ao Mac.
Túneis precisam ser restabelecidos se o ADB cair/reiniciar.

## Superfície de regressão

O patch é condicionado à feature `azsign-access-poc`:

- `Cargo.toml` da raiz e hbb_common: declara/propaga a feature, sem novas dependências Rust.
- `hbb_common/src/lib.rs`: disponibiliza módulo novo somente com a feature.
- `socket_client.rs`: hooks em TCP normal/local e UDP de registro/rebind;
  destinos fora da lista são recusados. UDP direto é recusado na PoC.
- `udp.rs`: variante adicional que preserva o loop original de registro, usando
  BytesCodec sobre TLS. Variantes Direct e Socks não mudam com feature desligada.
- `rendezvous_mediator.rs`: desativa listener direto neste build de teste.
- `flutter/ndk_arm.sh`: ativa a feature no build Android dedicado.
- `AndroidManifest.xml`: provider ADB e backup desabilitado; Gradle adiciona Bouncy Castle.
- Workflow: endpoints de laboratório, patches mantidos, versão/nome PoC.

Não altera traits compartilhadas, formato da senha, serviço de captura nem
controle de toque. Hooks de transporte não implementam autorização por ID/par
ou vínculo com conta real do CMS. A identidade privada em arquivo é passível de
extração em aparelho comprometido; Keystore/anti-clonagem não foram implementados.

`check-patch.mjs <checkout-1.4.9>` valida alvos em uma cópia temporária, sem tocar
no checkout de entrada. A compilação Android real continua sendo obrigatória.

## Recuperação gerenciada e tela Android — implementação de 05/10/2026

Branch `feat/azsign-device-recovery`, versão proposta `1.4.9-azsign-remote.24`
(build-number 4084; versionCode efetivo ARMv7 5084). Build APK validado; homologação física pendente. O workflow
aplica `recovery-apply.mjs` depois dos patches de acesso e de confirmação de senha,
sempre na tag 1.4.9. Mantém applicationId e assinatura para atualizar preservando
os dados privados; não desinstalar nem limpar dados para atualizar.

O Android 8+ consulta o CMS a cada 60 segundos com prova RSA da identidade local.
Não usa ADB, senha administrativa nem token compartilhado. Uma autorização explícita
do superadmin gera certificado inicialmente bloqueado e nova senha; só após a
persistência da senha e o recibo assinado o CMS libera o novo vínculo. O journal
permite retomar após queda de rede e não contém senha. A senha exibível fica cifrada
com AndroidKeyStore. Android anterior ao 8 não executa a recuperação nova.

`recovery.json` preserva origem HTTPS e CA mesmo após revogação remover `active.json`.
Para APK legado já revogado, preencher `recovery_origin` no workflow com a origem
HTTPS confiável do CMS (`https://app.azsign.com.br` nesta instalação). Sem chave
local preservada, exige novo provisionamento; a identidade não é recriada à força.
O CMS precisa da migration e de `RUSTDESK_ACCESS_RECOVERY_ENABLED=true`.

A tela mostra ID, senha gerenciada (revelada por ação local por 30 segundos), vínculo,
estado, compartilhamento e permissão de controle. Servidor, chave pública e proxy
são somente consulta. Senhas configuradas antes deste APK não são recuperadas do
hash RustDesk: nesses casos a tela orienta consultar o painel. Nome, launcher,
notificações e serviço de acessibilidade usam AZSign Remote; crédito e licenças
RustDesk continuam acessíveis. O SVG é o mesmo usado pelo desktop AZSign Remote.

### Superfície de regressão deste incremento

- `AzsignAccessIdentity.java`: assinatura adicional; prepare/enrollment/renewal existentes preservados.
- `AzsignRenewalHttp.java`: método separado para recovery; transporte de renewal original preservado.
- `MainApplication.kt`: inicia worker paralelo após o bootstrap/renewal existente.
- `MainActivity.kt`: dois métodos locais para estado público e revelação da senha gerenciada.
- `src/lib.rs`: inclui JNI novo somente Android; usa setter verificado e restart já existentes.
- `home_page.dart`: Android abre a tela de equipamento; caminho iOS permanece original.
- Manifest, strings, MainService e recursos launcher: identificação visual; IDs de canal,
  package, permissões, provedores e lógica de captura/controle permanecem existentes.
- Workflow: inclui arquivos novos, renderiza ícones e incrementa versão. Não atualiza submódulos.

Verificação local: patches completos sobre tag fixada; análise Dart da página; Java
compilado contra Android SDK 34; testes de prova, revogação, retry, expiração e
renovação. Essas verificações não substituem compilar o APK nem conectar/controlar
um aparelho real, reiniciar o box e repetir exclusão/recadastro entre empresas.


### Sem janela flutuante

A distribuição Android fixa `disable-floating-window=Y` pelo mecanismo nativo
`OVERWRITE_LOCAL_SETTINGS`, prevalecendo sobre preferências de versões antigas.
O serviço `FloatingWindowService` fica desabilitado no Manifest. A tela única não
oferece opção para reativá-lo. `MainActivity.onStop` consulta a configuração fixa
e não inicia a bolha; o compartilhamento não pede permissão para a bolha. Mantida
`SYSTEM_ALERT_WINDOW`, pois o fluxo existente de inicialização após boot também
a consulta. Captura, controle e notificação de serviço em primeiro plano continuam.
Superfície adicional: inicialização da configuração local fixa em hbb_common e
habilitação do serviço de overlay no Manifest, ambos restritos ao APK customizado.


Build concluído em 05/10/2026: https://github.com/rgazeredo/rustdesk/actions/runs/37308355523
(commit de código `a79692634d86488c8b37f9c8506bca475cf3d9b4`). APK ARMv7 de 27.177.344 bytes,
SHA-256 `4a0f729ab566a6636f4c2763ba1ad942781325e54b57547a301bfa8416b840b6`.
Assinatura verificada e igual à v22; package preservado `com.carriez.flutter_hbb`,
label AZSign Remote, versão `1.4.9-azsign-remote.24`/5084. Manifest do artefato confirma
FloatingWindowService desabilitado e MainService habilitado; ícone adaptativo aponta
para a arte AZSign Remote. Nenhuma instalação ou teste físico realizado nesta etapa.

## Revisão de interface após teste físico da v24 — código preparado

Usuário escolheu senha somente no painel. A tela passa a mostrar apenas ID,
estado e botões para permissões de tela/controle ausentes. Não mostra senha,
chave, servidores, proxy ou dados do vínculo. O canal local de revelação foi
removido e o cache cifrado introduzido na v24 é descartado; o setter nativo já
confirma persistência da senha RustDesk. ID usa `serverModel.fetchID()` a cada
consulta (antes o polling existia somente na antiga ServerPage).

Ícone adaptativo: inset nativo de 25% mantém o desenho dentro da área segura do
launcher do DC400. A tela usa PNG renderizado do mesmo SVG, evitando a perda do
símbolo principal causada pelo SVG aninhado no renderizador Flutter. Mesma marca,
sem novo desenho. Os controles de iniciar/parar/revelar senha foram removidos;
acionar uma permissão usa o fluxo nativo existente, sem desligar um serviço ativo.

Novo domínio solicitado `remote.azsign.com.br` já resolve para 18.230.75.197 em
05/10. Certificado TLS apresentado na porta 32116 ainda contém somente
`DNS:rustdesk.azsign.com.br`. Migração precisa de certificado com ambos os nomes,
configuração CMS/gateway e atualização coordenada dos perfis: renewal Android
normal não aceita alteração de perfil silenciosa e transporte limita os destinos
ao perfil provisionado. Não mudar apenas o HOST do workflow. Endereço antigo
permanece até concluir essa preparação, preservando as instalações existentes.
Nenhum novo APK gerado/instalado a partir desta revisão de interface ainda.

## Migração de domínio preparada — 05/10/2026

Gateway Lightsail já apresenta certificado da mesma CA com SAN dos dois nomes,
validado externamente em ambos nas portas 32116, 32117 e 32118. Validade até
04/12/2026; nenhuma CA/chave do dispositivo foi trocada. DNS antigo e anúncio
hbbs permanecem. CMS deve fixar perfis antigos antes de mudar defaults.

Android reconhece somente o par exato rustdesk.azsign.com.br/remote.azsign.com.br
como destinos lógicos equivalentes quando host E server_name do perfil pertencem
ao mesmo par. Socket, SNI, CA, certificado e portas continuam derivados do perfil
autenticado; não há conexão ao endereço recebido nem fallback direto. Instalações
com outros domínios continuam exigindo correspondência exata. Workflow preparado
com HOST/RELAY novos; perfil antigo continua funcionando na atualização do APK.

Superfície de regressão: `azsign_access.rs` altera somente a validação de destino
TCP/registro Android; `azsign_domain_alias.rs` contém a regra/testes isolados;
`apply.mjs` copia esse módulo para hbb_common no build; workflow muda os nomes
fixos. Caminho desktop não Android permanece exato; feature desligada não compila
este transporte. Revisão de minimização: nenhuma mudança em TLS, portas, CA,
Java renewal, permissões ou fallback. Dois testes Rust passaram em rustc 1.85,
incluindo ambos os sentidos, outros tenants/domínios, IP, loopback e sufixos falsos.
Suíte Java existente confirmou recusa de troca de perfil/CA durante renovação.
Compilação completa e teste físico ficam para o próximo APK, ainda não gerado.

Não ativar `RUSTDESK_ACCESS_DEVICE_GATEWAY_HOST/SERVER_NAME=remote.azsign.com.br`
no CMS antes de implantar o snapshot de perfis e instalar este APK nos dispositivos
que receberão novos cadastros/recuperações. APK v24 não contém os aliases. Manter
o gateway global e anúncio hbbs antigos preserva os desktops atuais. Migração
automática de identidades ativas não foi adicionada; elas renovam no perfil fixado.

## v25 gerada e instalada — 05/10/2026

Build https://github.com/rgazeredo/rustdesk/actions/runs/37346571257 concluído,
fonte `ebde80914dcb23930380efecdb0b4ab95a925cf3`. APK versão
`1.4.9-azsign-remote.25`/5085, 27.200.851 bytes, ARMv7; SHA256
`eab7203b1d6266684de97530e148ccbbc724079e62810163356a0ee140dca79c`.
Assinatura igual à v24. Manifest confirmou FloatingWindowService=false e
MainService=true. Atualização `adb install -r` no DC400 192.168.0.82 concluída,
identidade preservada. Tela mostra ID1.293.024.870, estado Aguardando autorização,
somente permissão de tela pendente, sem configuração/senha exposta ou bolha.
Screenshot/verification.json em azsign/output/artifacts/azsign-remote-v25/.

CMS/migrations implantados, 13 perfis antigos preservados. Ativação do novo
default e recuperação ainda NÃO executadas: revisão automática bloqueou a mudança
pela divergência com cadastro DC400xx/AZTV já vinculado a outro ID remoto.
Usuário pediu conduzir pessoalmente a autorização no painel. Não considerar
sessão gráfica, recuperação ou conexão no novo perfil homologadas.
Lista explícita CMS `RUSTDESK_ACCESS_DEVICE_GATEWAY_IDENTITY_IDS` foi adicionada
para impedir que aparelhos não atualizados recebam o domínio novo.
Superfície deste incremento Android: apenas versionamento no workflow, build e
instalação; comportamento vem dos commits de UI/aliases descritos acima.
