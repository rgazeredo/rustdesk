# APK PoC — não distribuir em produção

Base: tag RustDesk 1.4.9 + patches AZSign v14. Build somente pela branch
`azsign/access-control-poc-v15`. O workflow mantém a assinatura existente,
mas troca os endpoints pela identificação fictícia `azsign-poc.invalid` e
pela chave **pública** do laboratório. Nenhuma chave privada entra no build.

## Provisionamento

O provider `com.carriez.flutter_hbb.azsign.accesspoc` aceita somente escrita
via UID shell/root. Arquivos permitidos: `profile.json`, `ca.der`, `device.der`
e `device.key.der`. Não há leitura/exportação nem alteração de senha.
Destino: diretório privado do app, usuário Android 0; não homologado para
perfis secundários. O laboratório usa TLS 1.3 e identidade individual.

O profile contém host, nome TLS e portas separadas para registration,
rendezvous e relay. Configuração ausente/inválida causa falha fechada.
No laboratório do DC400, ADB reverse liga as portas 32116–32118 ao Mac.
Túneis precisam ser restabelecidos se o ADB cair/reiniciar.

## Superfície de regressão

O patch é condicionado à feature `azsign-access-poc`:

- `Cargo.toml` da raiz e hbb_common: declara/propaga a feature, sem novas dependências.
- `hbb_common/src/lib.rs`: disponibiliza módulo novo somente com a feature.
- `socket_client.rs`: hooks em TCP normal/local e UDP de registro/rebind;
  destinos fora da lista são recusados. UDP direto é recusado na PoC.
- `udp.rs`: variante adicional que preserva o loop original de registro, usando
  BytesCodec sobre TLS. Variantes Direct e Socks não mudam com feature desligada.
- `rendezvous_mediator.rs`: desativa listener direto neste build de teste.
- `flutter/ndk_arm.sh`: ativa a feature no build Android dedicado.
- `AndroidManifest.xml`: adiciona provider ADB exclusivo deste build.
- Workflow: endpoints de laboratório, patches mantidos, versão/nome PoC.

Não altera traits compartilhadas, formato da senha, serviço de captura nem
controle de toque. Hooks de transporte não implementam autorização por ID/par
ou vínculo com conta real do CMS. A identidade privada em arquivo é passível de
extração em aparelho comprometido; Keystore/anti-clonagem não foram implementados.

`check-patch.mjs <checkout-1.4.9>` valida alvos em uma cópia temporária, sem tocar
no checkout de entrada. A compilação Android real continua sendo obrigatória.
