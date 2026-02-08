{
  autoreconfHook,
  cairo,
  cppunit,
  fetchFromGitHub,
  fetchNpmDeps,
  lib,
  libcap,
  libpng,
  libreoffice-collabora,
  nodejs,
  npmHooks,
  pam,
  pango,
  pixman,
  pkg-config,
  poco,
  python3,
  rsync,
  stdenv,
  zstd,
  kdePackages,
  perl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "collabora-desktop";
  version = "25.04.8.1-1";
  src = fetchFromGitHub {
    owner = "CollaboraOnline";
    repo = "online";
    tag = "coda-${finalAttrs.version}";
    hash = "sha256-CwafnJiGjOnzA0yMIXlJU/jYnZlZFw0ulK76nZWWmhw=";
  };

  postPatch = ''
    cp ${./package-lock.json} ${finalAttrs.npmRoot}/package-lock.json

    patchShebangs browser/util/*.py coolwsd-systemplate-setup scripts/*
    substituteInPlace configure.ac --replace-fail '/usr/bin/env python3' python3
  '';

  nativeBuildInputs = [
    autoreconfHook
    perl
    nodejs
    npmHooks.npmConfigHook
    pkg-config
    python3
    python3.pkgs.lxml
    python3.pkgs.polib
    rsync
    # from CollaboraOnline/nix-build-support
    kdePackages.qtbase.dev
    kdePackages.qttools
    (stdenv.mkDerivation {
      name = "qtlibexec";
      src = kdePackages.qtbase;
      buildPhase = ''
        mkdir -p $out
        ln -s ${kdePackages.qtbase}/libexec $out/bin
      '';
    })
    kdePackages.qtbase
    kdePackages.qtwebengine
    kdePackages.wrapQtAppsHook
  ];

  buildInputs = [
    cairo
    cppunit
    libcap
    libpng
    pam
    pango
    pixman
    poco
    zstd
  ];

  configureFlags = [
    "--disable-werror"
    "--enable-silent-rules"
    "--with-lo-path=${libreoffice-collabora}/lib/collaboraoffice"
    "--with-lokit-path=${libreoffice-collabora.src}/include"
    "--enable-qtapp"
    "--enable-silent-rules"
    "--disable-ssl"
    #"--with-vendor=Collabora Productivity Limited"
    #"--with-app-name=Collabora Office"
    "--with-info-url=https://collaboraoffice.com/"
  ];

  enableParallelBuilding = true;

  postInstall = ''
    cp --no-preserve=mode ${libreoffice-collabora}/lib/collaboraoffice/LICENSE.html $out/LICENSE.html
    python3 scripts/insert-coda-license.py $out/LICENSE.html CODA-THIRDPARTYLICENSES.html
  '';

  npmDeps = fetchNpmDeps {
    unpackPhase = "true";
    # TODO: Use upstream `npm-shrinkwrap.json` once it's fixed
    # https://github.com/CollaboraOnline/online/issues/9644
    postPatch = ''
      cp ${./package-lock.json} package-lock.json
    '';
    hash = "sha256-xS1vBfsG8PYsfiLlhehaddIuyiv4vlG7v2mHihuMROc=";
  };

  npmRoot = "browser";

  passthru = {
    libreoffice = libreoffice-collabora; # Used by NixOS module.
    updateScript = ./update.sh;
  };

  meta = {
    description = "Collaborative office suite based on LibreOffice technology";
    license = lib.licenses.mpl20;
    homepage = "https://www.collaboraonline.com";
    platforms = lib.platforms.linux;
    maintainers = [ lib.maintainers.xzfc ];
    teams = [ lib.teams.ngi ];
  };
})
