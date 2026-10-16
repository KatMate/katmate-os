# tty1's autologin starts the installer once per boot; every other login is a
# plain shell.
if [[ "$(tty)" == /dev/tty1 && ! -e /run/katmate-install.started ]]; then
  : >/run/katmate-install.started
  katmate-install
fi
