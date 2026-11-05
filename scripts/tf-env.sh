#!/usr/bin/env bash
# Source me: `. scripts/tf-env.sh`. Builds TF_ENCRYPTION from TF_STATE_PASSPHRASE (never printed).
: "${TF_STATE_PASSPHRASE:?set TF_STATE_PASSPHRASE (>=16 chars) in your shell or CI secrets}"
[ "${#TF_STATE_PASSPHRASE}" -ge 16 ] || { echo "TF_STATE_PASSPHRASE too short" >&2; return 1; }
export TF_ENCRYPTION="
key_provider \"pbkdf2\" \"main\" { passphrase = \"${TF_STATE_PASSPHRASE}\" }
method \"aes_gcm\" \"main\" { keys = key_provider.pbkdf2.main }
state { method = method.aes_gcm.main
        enforced = true }
"
