# AZSign Remote — teste MSIX Windows x64

Pacote experimental para homologação antes da Microsoft Store. Não publicado na
loja e não assinado pela Microsoft. Reutiliza o runtime Remote 1.5.2 validado,
sem mudança de APK, CMS, gateway ou protocolo de autorização.

## Instalar para teste

Use Windows 10 1809+ ou Windows 11 x64, preferencialmente uma VM ou um perfil
Windows dedicado. Feche outras cópias do Remote. A identidade MSIX é de teste,
mas o aplicativo conserva o nome interno AZSignRemotePilot: não se deve presumir
isolamento das configurações/credenciais da versão instalada ou portátil.

O certificado público `.cer` acompanha o pacote. Sua chave privada não é
distribuída e é destruída no runner após assinar. O certificado vence em 30 dias;
consulte SIGNING-CERTIFICATE.txt para identificar a emissão. Uma nova execução
de CI cria outra chave, portanto pacotes de execuções distintas podem não permitir
atualização direta. A identidade/certificado da Store serão definidos no Partner
Center e serão diferentes desta identidade de laboratório.

1. Confira a origem dos arquivos e os SHA-256 em SHA256SUMS.txt.
2. Em PowerShell **como administrador**, na pasta dos arquivos, importe somente
   o certificado público de teste em Pessoas Confiáveis (não em Raízes):

   ```powershell
   Import-Certificate -FilePath .\AZSign-Remote-Test.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
   ```

3. No PowerShell **normal do usuário que fará o teste**, instale:

   ```powershell
   Add-AppxPackage -Path .\AZSign-Remote-Test-1.5.2.0-x64.msix
   ```

4. Abra **AZSign Remote (Teste MSIX)** no menu Iniciar. Entre com AZSign pelo
   navegador e teste um player autorizado. Para testar atualização mantendo os
   dados, feche o Remote e instale o segundo pacote:

   ```powershell
   Add-AppxPackage -Path .\AZSign-Remote-Test-1.5.2.1-x64.msix
   ```

Os dois pacotes têm o mesmo runtime; a revisão `.1` existe para testar atualização.
Se houver mais de um aplicativo associado ao link, o Windows pode pedir a escolha
do aplicativo. Não desative Smart App Control, Defender, SmartScreen ou políticas
da empresa para instalar este teste. Se bloqueado, registre a mensagem e use uma
máquina de homologação autorizada. Confiar no certificado é uma etapa exclusiva
do teste local; a distribuição aprovada pela Store terá assinatura da Microsoft.

## Remover o teste

Use Aplicativos do Windows ou, no PowerShell do usuário:

```powershell
Get-AppxPackage -Name AZSign.Remote.Test | Remove-AppxPackage
```

Dados virtualizados do MSIX podem ser removidos na desinstalação, diferentemente
do instalador EXE. Dados preexistentes fora do pacote podem permanecer. Use Sair
antes de remover se desejar encerrar a sessão. Para retirar a confiança no
certificado, no PowerShell como administrador, na pasta dos arquivos:

```powershell
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new((Resolve-Path .\AZSign-Remote-Test.cer).Path)
Remove-Item "Cert:\LocalMachine\TrustedPeople\$($cert.Thumbprint)"
```

## Verificações

CI: validação do manifesto pelo MakeAppx; assinatura de teste; instalação;
leitura da identidade de uma instalação não empacotada; round trip de DPAPI pela
DLL real em contexto MSIX; persistência da chave privada (comparando apenas o hash
do CSR público) após novo processo e atualização; abertura fria/quente pelo
protocolo; identidade MSIX do processo real; virtualização do Registro;
desinstalação preservando a identidade legada. O probe nativo é ferramenta de
diagnóstico externa ao pacote, executada por Invoke-CommandInDesktopPackage.

A homologação interativa ainda deve conferir login, catálogo, vídeo, áudio,
teclado, transferência, bloqueio/liberação e logout em Windows 10/11. Não confundir
os testes de empacotamento com aprovação da Store ou teste ponta a ponta com box.

## Compilar

Workflow `.github/workflows/azsign-msix-test.yml`. A prova de conceito fixa o ZIP,
SHA-256 e commit de runtime da entrega aprovada `36916068285`; não usa binários
arbitrários nem inclui chaves de assinatura nos artefatos. O artefato de origem
do GitHub tem retenção limitada. Depois que expirar, será necessário disponibilizar
o mesmo ZIP verificado ou atualizar a origem após nova validação.

`package.ps1` exige Windows SDK e um certificado de teste local. Cria os assets a
partir do ícone AZSign existente e mantém a aplicação desktop como full trust,
sem serviço, driver, elevação ou capacidade para modificar pastas protegidas.

Antes da Store: substituir Name/Publisher pelos valores reservados na conta;
revalidar migração de dados e escolha do protocolo entre instalações; executar
Windows App Certification Kit e homologação ponta a ponta; preparar política de
privacidade, descrição, imagens e conta de demonstração para certificação.
`runFullTrust` deve ser justificado como cliente desktop de suporte a players.
A licença AGPL do fork RustDesk e o acesso ao código correspondente permanecem.
