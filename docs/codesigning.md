# Local code-signing identity

`script/build_and_run.sh` signs the iLaunch bundle (Sparkle helpers first,
then `Sparkle.framework`, then the app) with a stable self-signed identity,
`"iLaunch Local Signing"`, instead of ad-hoc (`--sign -`).

## Why this exists

macOS TCC (Privacy & Security > App Management, Accessibility) stores each
grant together with the app's designated requirement. Ad-hoc signing yields
`cdhash H"..."`, which changes on every build, so every update looked like a
new app and the grant was reset. With a stable certificate the requirement is

    identifier "com.ilaunch.iLaunch" and certificate leaf = H"<cert hash>"

which is identical across builds as long as the same certificate signs them.

Verify a build:

```bash
codesign -dr - dist/iLaunch.app
# want:  designated => identifier "com.ilaunch.iLaunch" and certificate leaf = H"..."
# NOT:   designated => cdhash H"..."
```

The build script fails if the identity is missing (no silent ad-hoc fallback)
or if the resulting requirement lacks `certificate leaf`. Set `SIGN_IDENTITY=-`
to force ad-hoc deliberately (grants will then reset on every build).

## Recreating the identity

Check first: `security find-identity -v -p codesigning` should list
`"iLaunch Local Signing"`. If not, recreate it. The certificate MUST carry
`basicConstraints CA:FALSE`, `keyUsage digitalSignature` and
`extendedKeyUsage codeSigning`; without them the identity imports but is
reported invalid ("Invalid Key Usage for policy").

```bash
# 1. Self-signed cert with the right extensions.
openssl req -x509 -newkey rsa:2048 -keyout /tmp/il_key.pem -out /tmp/il_cert.pem \
  -days 3650 -nodes -subj "/CN=iLaunch Local Signing" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# 2. PKCS12 bundle. `security` can't read OpenSSL 3.x's default encryption: -legacy.
openssl pkcs12 -export -legacy -inkey /tmp/il_key.pem -in /tmp/il_cert.pem \
  -out /tmp/il_cert.p12 -passout pass:temp123

# 3. Import into the login keychain, usable by codesign.
security import /tmp/il_cert.p12 -k ~/Library/Keychains/login.keychain-db \
  -P temp123 -T /usr/bin/codesign

# 4. Trust it for code signing (`trustRoot`, not `trustAsRoot`).
security add-trusted-cert -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db /tmp/il_cert.pem

# 5. Clean up, then confirm.
rm -f /tmp/il_key.pem /tmp/il_cert.pem /tmp/il_cert.p12
security find-identity -v -p codesigning
```

## Backup and loss

A PKCS12 backup and its password live at
`~/.config/ilaunch/ilaunch_local_signing.p12` and `.p12.pass` (outside the
repo; never commit them). Also copy them somewhere off this machine. The
identity is not in git and has no cloud backup. If it is lost, a new
certificate has a different leaf hash, so every user must re-grant once.

Releases must be built on the machine that holds this identity.

## One-time migration (first release under this identity, 1.9.14)

The old grant is bound to a cdhash requirement that will never match again.
After installing 1.9.14:

1. System Settings > Privacy & Security > App Management (and Accessibility
   if used).
2. Remove (−) any existing iLaunch entry; toggling it off/on does not refresh
   the stored requirement.
3. Add (+) iLaunch (or enable it when prompted).

From then on, updates signed by the same identity keep the grant.
