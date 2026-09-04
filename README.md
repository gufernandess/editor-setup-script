# editor-setup

Instala extensões, fonte (JetBrains Mono), settings, keybindings e
configuração de MCP servers num editor da família VS Code (Kiro, VS
Code, forks), a partir do snapshot capturado da instalação local do
Kiro em `customizations.json`.

## Uso

Abra o terminal integrado do editor que você quer configurar e rode:

    bash install-editor-setup.sh

O script detecta o editor automaticamente a partir do terminal em que
está rodando (não funciona se executado fora do terminal integrado de
um editor da família VS Code). Ele não interrompe no primeiro erro:
cada etapa (extensões, fonte, settings, keybindings, mcp) roda de
forma independente, e o resumo no final mostra o que funcionou, o que
falhou e o que foi pulado.

Log completo em `~/.editor-setup-install.log`.

## Requisitos

bash, python3, curl, unzip, fontconfig (`fc-cache`).

## Limitações conhecidas

- Servidores MCP que exigem login interativo (ex. Figma) precisam de
  autenticação manual depois de aplicado o `mcp.json`.
- `customizations.json` é um snapshot estático capturado em
  2026-09-03 a partir da instalação local do Kiro - não é
  resincronizado automaticamente se você mudar extensões/settings
  depois.
- Validado até agora apenas contra uma instalação manual (tarball) do
  Kiro. Comportamento em instalações via snap/pacman/pamac ainda não
  foi testado - ver `docs/superpowers/specs/` para o design da
  detecção.
