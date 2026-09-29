# Links AZSign Remote

Contrato: `azsign-remote://connection/new/<ID numérico de 6 a 16 dígitos>`.
Não aceita senha, query string, fragmento, host de gateway ou chave no link.

Na versão 1.5.2, o link inicia a conexão diretamente após validar a sessão AZSign.
Sem sessão, aguarda login pelo navegador e continua automaticamente após aprovação.
Usa o mesmo enrollment nativo do catálogo; gateway/CMS continuam autorizando o player,
aplicando bloqueios e recusando sessões expiradas/revogadas. Logout limpa o alvo.
Identificadores internos de armazenamento/Keychain/DPAPI não são renomeados.

## Distribuição coordenada

- Requer novas builds macOS e Windows. A versão pública 1.5.0 anterior não
  registra este protocolo; não publicar somente a alteração do painel.
- macOS: build-desktop-macos.sh fornece e verifica o URL scheme no Info.plist.
  Instalar a nova aplicação na pasta Aplicativos.
- Windows portátil: extrair em pasta permanente e abrir AZSign Remote.exe uma
  vez. Registra HKCU/Software/Classes/azsign-remote, sem administrador. Se mover
  a pasta, abrir novamente para atualizar o caminho. Não altera rustdesk://.
- Nenhuma alteração no APK Android, no Setup, no gateway ou nos certificados.

## Homologação dos novos pacotes (pendente)

Testar o link do painel no navegador com app fechado, aberto e minimizado,
antes/depois do login. Confirmar que não cria outra instância no Windows.
Testar login recusado, conta/empresa errada, bloqueio e logout. Testar caminhos
Windows com espaços e abertura após mover a pasta e executar novamente.
Em macOS, conferir a associação do sistema após substituir a aplicação.

Testes automatizados Flutter cobrem parser, alvo pendente antes do login,
conexão direta/enrollment, falha do CMS sem retry automático e limpeza ao sair. Eles não
substituem a verificação do protocolo registrado no sistema operacional.
