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
