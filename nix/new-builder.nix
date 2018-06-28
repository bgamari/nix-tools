{ stdenv, lib, haskellLib, ghc, fetchurl, writeText, runCommand, pkgconfig, callPackage }:

{ flags ? {}
, package ? {}
, components ? {}

, name ? "${package.identifier.name}-${package.identifier.version}"
, sha256 ? null
, src ? fetchurl { url = "mirror://hackage/${name}.tar.gz"; inherit sha256; }
, cabalFile ? null
}@config:

let
  defaultSetupSrc = builtins.toFile "Setup.hs" ''
    import Distribution.Simple
    main = defaultMain
  '';
  defaultSetup = runCommand "default-Setup" { nativeBuildInputs = [ghc]; } ''
    ghc ${defaultSetupSrc} --make -o $out
  '';

  setup = stdenv.mkDerivation {
    name = "${name}-setup";
    nativeBuildInputs = [ghc];
    inherit src;
    phases = ["unpackPhase" "buildPhase" "installPhase"];
    buildPhase = ''
      setup=${defaultSetup}
      for f in Setup.hs Setup.lhs; do
        if [ -f $f ]; then
          if ! (diff $f ${defaultSetupSrc} > /dev/null); then
            echo Compiling package $f
            ghc $f --make -o ./Setup
            setup=$(pwd)/Setup
          else
            echo Using default Setup
          fi
          break
        fi
      done
    '';

    installPhase = ''
      mkdir -p $out/bin
      install $setup $out/bin/Setup
    '';
  };

  comp-builder = callPackage ./comp-builder.nix { inherit ghc haskellLib; };

  buildComp = componentId: component: comp-builder {
    inherit componentId package name src flags setup cabalFile;
    component =
      let
        nonNullLists = fs: component // lib.genAttrs fs (field:
          if component ? ${field}
            then builtins.filter (x: x != null) component.${field}
            else []);
      in {
        allowNewer = false;
        allowOlder = false;
      } // nonNullLists [
        "depends"
        "libs"
        "frameworks"
        "pkgconfig"
        "build-tools"
        "configureFlags"
      ];
  };

in {
  components = haskellLib.applyComponents buildComp components;
  inherit (package) identifier;
  inherit setup;
}
