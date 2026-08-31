# passkey/ — software CTAP2 virtual authenticator
#
# This package emulates a FIDO2 security key in user-space by
# - listening on /dev/uhid for CTAPHID traffic from the host (IB Gateway),
# - answering CTAP2 getInfo / makeCredential / getAssertion with a
#   pre-imported EC private key extracted from a Bitwarden vault,
# - so that IB Gateway's "Use your Passkey device" prompt is satisfied
#   without a physical token.
#
# The module is intentionally free of any Qt/GUI dependency; it runs
# headless inside the Docker container and is started from image-files/start.sh
# before IBC launches IB Gateway.
