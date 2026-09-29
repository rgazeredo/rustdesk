# AZSign Remote — Windows x64

Extraia o ZIP inteiro para uma pasta e abra `AZSign Remote.exe`.

Versão 1.5.2: ao abrir, registra `azsign-remote://` para o usuário atual.
Mantenha a pasta em um local permanente. Se movê-la, abra o executável novamente.
O link do painel inicia a conexão diretamente. Se necessário, entre com AZSign;
o acesso continua após o login, sem confirmação adicional no aplicativo.
Não envia senha pelo link e não altera a associação `rustdesk://` existente.

O catálogo permite buscar pelo nome em todas as páginas. Ao mudar a busca,
os resultados voltam à primeira página; o botão de limpar restaura a lista.
A troca do nome não muda os diretórios de dados, certificados ou credenciais.
Não execute diretamente de dentro do ZIP nem copie apenas o executável.
Não precisa instalar serviço, configurar proxy ou executar como administrador.

Use Entrar com AZSign e autorize no navegador. A empresa deve estar habilitada
para acesso remoto no CMS. O catálogo respeita as permissões do usuário.
O Windows protege token/chave privada com DPAPI do usuário atual; nunca copie
o armazenamento local para outra máquina. Em outro computador, entre novamente.

Build sem assinatura Authenticode: o Windows pode exibir aviso de editor
desconhecido. Confira origem e SHA-256 antes de executar. Não desative antivírus.

Homologar antes de distribuir: login, catálogo, conexão, envio/recebimento,
bloqueio durante sessão, recusa de reconexão, liberação, logout e reinício.
Uma compilação bem-sucedida não substitui estes testes interativos.

Primeira transferência Android: mantém a pasta salva ou a pasta absoluta
informada pelo aparelho. Sem uma pasta absoluta conhecida, tenta o alias Android
`/sdcard`, sujeito às permissões do aparelho, antes da solicitação de Home vazia.
Não fixa `/storage/emulated/0` nem modifica permissões. Homologar também num
perfil Windows novo, sem pasta remota salva: reabrir com caminho salvo não
comprova a primeira abertura.

Antes da entrega, com controle e transferência abertos no Windows:
- Bloquear somente o player de teste no painel superadmin. Confirmar queda dos
  dois canais e recusa de novas conexões; conferir encerramentos no histórico.
- Liberar e abrir novas sessões de controle e transferência; conferir o histórico.
- Usar Sair no aplicativo com os dois canais abertos. Confirmar encerramento,
  catálogo removido e impossibilidade de reconectar sem nova autorização.
- Fechar/reabrir após logout, confirmar que não resta sessão autenticada, e
  autorizar novamente para testar reconexão. Não compartilhar senhas ou tokens.

Estado de homologação: o operador confirmou no Windows controle, teclado e
envio/recebimento em 28/09/2026. Primeira abertura corrigida, bloqueio/liberação
e logout na nova build ainda aguardam validação física; não distribuir como
homologado até concluir esses passos.

Baseado em RustDesk, sob AGPL-3.0. Código correspondente e instruções:
https://github.com/rgazeredo/rustdesk/tree/feat/azsign-desktop-windows
Consulte também LICENSE-RustDesk.txt distribuído neste pacote.
