# AZSign Remote — piloto Windows x64

Extraia o ZIP inteiro para uma pasta e abra `AZSignRemotePilot.exe`.
Não execute diretamente de dentro do ZIP nem copie apenas o executável.
Não precisa instalar serviço, configurar proxy ou executar como administrador.

Use Entrar com AZSign e autorize no navegador. A empresa deve estar habilitada
para acesso remoto no CMS. O catálogo respeita as permissões do usuário.
O Windows protege token/chave privada com DPAPI do usuário atual; nunca copie
o armazenamento local para outra máquina. Em outro computador, entre novamente.

Build piloto sem assinatura Authenticode: o Windows pode exibir aviso de editor
desconhecido. Confira origem e SHA-256 antes de executar. Não desative antivírus.

Homologar antes de distribuir: login, catálogo, conexão, envio/recebimento,
bloqueio durante sessão, recusa de reconexão, liberação, logout e reinício.
Uma compilação bem-sucedida não substitui estes testes interativos.

Baseado em RustDesk, sob AGPL-3.0. Código correspondente e instruções:
https://github.com/rgazeredo/rustdesk/tree/feat/azsign-desktop-windows
Consulte também LICENSE-RustDesk.txt distribuído neste pacote.
