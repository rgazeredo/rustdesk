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
(versionCode 4084). Build APK e homologação física ainda pendentes. O workflow
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
