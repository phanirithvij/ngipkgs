{
  lib,
  rustPlatform,
  fetchgit,
}:

rustPlatform.buildRustPackage {
  pname = "muchrooms";
  version = "0-unstable-2025-09-04";

  src = fetchgit {
    url = "https://code.bouah.net/pep/muchrooms";
    rev = "b2f8131fe12009168e429d354a0dc76d66bb0caf";
    hash = "sha256-+A3LP5D7Bu8nMEbHNghDACbJKR+cOqaoDDHgXFSToZM=";
  };

  # upstream has no cargo.lock
  # Tried to generate it via crago fetch --locked and cargo generate-lockfile
  # But the project has a scansion 0.1 dependency which isn't linked via a git dependency
  # it is at https://code.bouah.net/pep/scansion-rs/tags
  # That dependency and muchrooms pin different git versions of xmpp-rs
  # which give rise to 3 jid-0.12.0 versions, two using git revs, resulting it nix disallowing
  # two of the same "jid-0.12.0" in outputHashes
  # Follow https://github.com/NixOS/nixpkgs/pull/387337
  # Only solution is to advance upstream to correct versions where it doesn't happen
  # Or patch all of them to use the latest xmpp-rs and generate cargo lock that way (TODO)
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "jid-0.12.0" = lib.fakeHash;
    };
  };

  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';

  meta = {
    description = "TBA";
    homepage = "https://code.bouah.net/pep/muchrooms";
    license = lib.licenses.agpl3Plus;
    maintainers = with lib.maintainers; [ phanirithvij ];
    teams = with lib.teams; [ ngi ];
    mainProgram = "muchrooms";
  };
}
