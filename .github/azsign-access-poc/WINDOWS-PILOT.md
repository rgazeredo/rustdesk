# AZSign Remote — Windows x64

Prova de conceito para Microsoft Store: veja [teste MSIX](msix/README.md).
O MSIX usa identidade/certificado de laboratório e não substitui as entregas abaixo.

O instalador `AZSign-Remote-Setup-1.5.2-windows-x64.exe` instala para o usuário
atual, sem administrador, em `%LOCALAPPDATA%\Programs\AZSign Remote` por padrão.
Cria atalho no menu Iniciar, oferece atalho na área de trabalho e registra o link
`azsign-remote://` durante a instalação. Pode ser removido em Aplicativos do Windows.
Reexecutar o instalador atualiza/repara os arquivos; feche sessões antes de atualizar.
Configurações e credenciais do usuário são preservadas, inclusive ao desinstalar.
Para revogar a sessão, use Sair no Remote antes de remover o aplicativo.

A versão ZIP continua disponível: extraia o ZIP inteiro para uma pasta e abra
`AZSign Remote.exe`. As orientações sobre mover a pasta abaixo valem para o ZIP.

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

## Empacotamento Windows

O workflow `azsign-windows-pilot.yml` gera ZIP e instalador Inno Setup 6 com os
mesmos binários. O job de empacotamento exige testes de instalação, integridade,
atalhos, protocolo, abertura, reparo e desinstalação antes de disponibilizar o artefato.
O AppId do instalador é AZSignRemote; o armazenamento interno AZSignRemotePilot
permanece inalterado. Não instala serviços, drivers nem associa rustdesk://.
O desinstalador remove apenas arquivos registrados pelo instalador e só remove
azsign-remote:// se o comando ainda apontar para a instalação removida.
Abrir uma cópia portátil depois de instalar pode reassociar o protocolo a ela;
reabra a cópia instalada para restaurar a associação.

Para empacotar um bundle Windows já preparado, em PowerShell com Inno Setup 6:

```powershell
./.github/azsign-access-poc/package-desktop-windows.ps1 -BundleDir C:\build\Remote -OutputDir C:\build\installer
```

A versão é lida do pubspec.yaml. O bundle deve conter licença, BUILD-COMMIT.txt,
DLLs nativas, runtime Visual C++ e assets Flutter completos, como preparado no CI.
O instalador ainda não tem assinatura Authenticode; o empacotamento não elimina
avisos SmartScreen/Smart App Control. Homologar também em Windows 10/11 com usuário
padrão e instalação interativa. Os testes automáticos usam runner descartável.
