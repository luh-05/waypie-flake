{
  description = "Waypie - Kando-like radial menu for Wayland";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Upstream source, pinned through flake.lock (bump with `nix flake update waypie-src`)
    waypie-src = {
      url = "github:rywby-dot/waypie";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, waypie-src }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      cargoToml = builtins.fromTOML (builtins.readFile "${waypie-src}/Cargo.toml");
      pyproject = builtins.fromTOML (builtins.readFile "${waypie-src}/pyproject.toml");

      overlay = final: prev: {
        # GTK4 configurator (Python)
        waypie-config = final.python3Packages.buildPythonApplication {
          pname = "waypie-config";
          version = pyproject.project.version;
          src = waypie-src;
          pyproject = true;

          build-system = [ final.python3Packages.hatchling ];
          dependencies = with final.python3Packages; [
            pycairo
            pygobject3
          ];

          nativeBuildInputs = [
            final.wrapGAppsHook4
            final.gobject-introspection
          ];
          buildInputs = [
            final.gtk4
            final.glib
            final.pango
            final.gdk-pixbuf
          ];

          # Let wrapGAppsHook4 wrap the python entry point
          dontWrapGApps = true;
          preFixup = ''
            makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
          '';

          doCheck = false;

          meta = {
            description = "GTK configurator for the Waypie radial menu";
            homepage = "https://github.com/rywby-dot/waypie";
            license = final.lib.licenses.mit;
            mainProgram = "waypie-config";
          };
        };

        # Rust runtime
        waypie = final.rustPlatform.buildRustPackage rec {
          pname = "waypie";
          version = cargoToml.package.version;
          src = waypie-src;
          cargoLock.lockFile = "${waypie-src}/Cargo.lock";

          nativeBuildInputs = [
            final.pkg-config
            final.makeWrapper
          ];
          buildInputs = [
            final.libxkbcommon
            final.fontconfig
          ];

          doCheck = false;

          postInstall = ''
            # Default config/style/icons, used by the home-manager module to seed ~/.config/waypie
            mkdir -p $out/share/waypie
            cp config/config* config/style*.css $out/share/waypie/
            if [ -d config/icons ]; then
              cp -R config/icons $out/share/waypie/icons
            fi
          '';

          # `waypie --configure` launches `waypie-config`, so put it on PATH.
          # Also add an rpath in case libxkbcommon is loaded at runtime.
          postFixup = ''
            patchelf --add-rpath ${final.lib.makeLibraryPath buildInputs} $out/bin/waypie
            wrapProgram $out/bin/waypie \
              --prefix PATH : ${final.lib.makeBinPath [ final.waypie-config ]}
          '';

          meta = {
            description = "Lightweight Kando-like radial menu for Wayland";
            homepage = "https://github.com/rywby-dot/waypie";
            license = final.lib.licenses.mit;
            mainProgram = "waypie";
            platforms = final.lib.platforms.linux;
          };
        };
      };
    in
    {
      overlays.default = overlay;

      packages = forAllSystems (
        pkgs:
        let
          p = pkgs.extend overlay;
        in
        {
          inherit (p) waypie waypie-config;
          default = p.waypie;
        }
      );

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.waypie}/bin/waypie";
        };
        config = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.waypie-config}/bin/waypie-config";
        };
      });

      homeManagerModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs.waypie;
        in
        {
          options.programs.waypie = {
            enable = lib.mkEnableOption "Waypie, a Kando-like radial menu for Wayland";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.waypie;
              defaultText = lib.literalExpression "waypie-flake.packages.\${system}.waypie";
              description = "The waypie package (includes the runtime; the configurator is on its PATH).";
            };

            configuratorPackage = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.waypie-config;
              defaultText = lib.literalExpression "waypie-flake.packages.\${system}.waypie-config";
              description = "The waypie-config package, installed so `waypie-config` is available in your profile.";
            };

            seedConfig = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Copy Waypie's bundled default config, style files and icons into
                ~/.config/waypie on activation, but only if they don't exist yet.
                Existing files are never overwritten. The files are real, writable
                files (not store symlinks), because the graphical configurator
                edits ~/.config/waypie/config.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [
              cfg.package
              cfg.configuratorPackage
            ];

            home.activation.waypieSeedConfig = lib.mkIf cfg.seedConfig (
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                src="${cfg.package}/share/waypie"
                dst="${config.xdg.configHome}/waypie"

                run ${pkgs.coreutils}/bin/mkdir -p "$dst/icons"

                for f in "$src"/config* "$src"/style*.css; do
                  [ -e "$f" ] || continue
                  if [ ! -e "$dst/$(basename "$f")" ]; then
                    run ${pkgs.coreutils}/bin/install -m 644 "$f" "$dst/$(basename "$f")"
                  fi
                done

                if [ -d "$src/icons" ]; then
                  run ${pkgs.coreutils}/bin/cp -R --update=none --no-preserve=mode "$src/icons/." "$dst/icons/"
                fi
              ''
            );
          };
        };
    };
}

