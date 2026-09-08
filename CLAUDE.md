# glm-review — istruzioni per Claude Code

- **README sempre aggiornato**: ogni modifica a comandi, flag, variabili di configurazione, layout del repo o comportamento dello script DEVE essere riflessa in `README.md` nello stesso commit (tabelle comandi/flag/configurazione, esempi, troubleshooting, layout).
- Bump di `version` in `.claude-plugin/plugin.json` e `.claude-plugin/marketplace.json` (tenerle allineate) a ogni release con modifiche funzionali.
- Lo script `scripts/glm-companion.sh` deve restare compatibile con bash 3.2 (macOS): niente `declare -A`, `readarray`, `${var,,}`.
- Validare prima di committare: `claude plugin validate .` e `bash -n scripts/glm-companion.sh`.
- Push su **entrambi i remote**: `origin` (GitHub) e `gitea` (dev.asp.messina.it).
