# glm-review — istruzioni per Claude Code

- **README sempre aggiornato**: ogni modifica a comandi, flag, variabili di configurazione, layout del repo o comportamento dello script DEVE essere riflessa in `README.md` nello stesso commit (tabelle comandi/flag/configurazione, esempi, troubleshooting, layout).
- Bump di `version` in `.claude-plugin/plugin.json` e `.claude-plugin/marketplace.json` (tenerle allineate) a ogni release con modifiche funzionali.
- Lo script `scripts/glm-companion.sh` deve restare compatibile con bash 3.2 (macOS): niente `declare -A`, `readarray`, `${var,,}`.
- Validare prima di committare: `claude plugin validate .`, `bash -n scripts/glm-companion.sh` e `bash tests/companion-test.sh` (test di regressione con stub di `claude`, senza chiamate API). Ogni bug fix o modifica di comportamento dello script va coperto da un test in `tests/companion-test.sh`.
- Non modificare `scripts/glm-companion.sh` mentre una review è in esecuzione: bash legge lo script incrementalmente e una riscrittura a metà corsa produce errori di sintassi spuri.
- Push **sempre su entrambi i remote, branch `main`**: `origin` è configurato con doppio push-url (GitHub + Gitea dev.asp.messina.it), quindi `git push origin main` li aggiorna entrambi in un colpo solo. Dopo ogni push verificare l'allineamento (`git ls-remote origin main` / `git ls-remote gitea main`). Se il doppio push-url mancasse (clone fresco), ripristinarlo con:
  `git remote set-url --add --push origin https://github.com/deduzzo/glm-review.git && git remote set-url --add --push origin https://dev.asp.messina.it/asp5_messina/glm-review.git`
