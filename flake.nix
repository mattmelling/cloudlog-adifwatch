{
  description = "Automatic upload of ADIF log to CloudLog";
  inputs = {
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, ... }: {
    devShells.x86_64-linux.default = let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in pkgs.mkShell {
      buildInputs = with pkgs; [
        rustc
        cargo
      ];
    };
    packages.x86_64-linux = {
      default = self.packages.x86_64-linux.cloudlog-adifwatch;
      cloudlog-adifwatch = let
        pkgs = import nixpkgs { system = "x86_64-linux"; };
      in pkgs.rustPlatform.buildRustPackage {
        pname = "cloudlog-adifwatch";
        version = "0.0.14";
        src = ./.;
        cargoSha256 = "sha256-Jjuw1AbbGSf/NrhGqTFJDrNJ8nemAwDhg48v8GFKnv8=";
        RUSTC_BOOTSTRAP = 1;
      };
    };
    checks.x86_64-linux.cloudlog-adifwatch = let
      test = import (nixpkgs + "/nixos/lib/testing-python.nix") {
        system = "x86_64-linux";
      };
    in test.simpleTest {
      name = "cloudlog-adifwatch";
      nodes.machine = { ... }: {
        imports = [ self.nixosModules.default ];
        nixpkgs.overlays = [ self.overlays.default ];
        services = {
          cloudlog-adifwatch = {
            enable = true;
            watchers = {
              wsjtx = "/etc/adif";
            };
            key = "/etc/cloudlog";
            host = "http://localhost";
          };
        };

        # Create some stub files to satisfy the service
        environment.etc.cloudlog.text = "key";
        environment.etc.adif.text = "";
      };
      testScript = ''
        machine.wait_for_unit('cloudlog-adifwatch-wsjtx.service')
      '';
    };
    hydraJobs = { inherit (self) packages checks; };
    overlays.default = (final: prev: {
      cloudlog-adifwatch = self.packages.x86_64-linux.cloudlog-adifwatch;
    });
    nixosModules.default = { pkgs, config, lib, ... }:
      let
        cfg = config.services.cloudlog-adifwatch;
        services = lib.mapAttrsToList (name: path: {
          name = "cloudlog-adifwatch-${name}";
          value = {
            description = "cloudlog-adifwatch ${name}";
            enable = true;
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.cloudlog-adifwatch}/bin/cloudlog-adifwatch ${cfg.host} ${cfg.key} ${toString cfg.station_id} ${path}";
            };
          };
        }) cfg.watchers;
      in
        {
          options = with lib.types; {
            services.cloudlog-adifwatch = {
              enable = lib.mkEnableOption "cloudlog-adifwatch";
              watchers = lib.mkOption {
                type = attrsOf str;
                default = { };
                description = "Attrs of files to watch.";
                example = {
                  wsjtx = "/home/user/wsjtx/wsjtx.adi";
                };
              };
              key = lib.mkOption {
                type = str;
                description = "Path to key for Cloudlog instance.";
              };
              host = lib.mkOption {
                type = str;
                description = "Hostname of Cloudlog instance.";
              };
              station_id = lib.mkOption {
                type = int;
                description = "Station Logbook ID";
                default = 1;
              };
            };
          };
          config = lib.mkIf cfg.enable {
            systemd.services = builtins.listToAttrs services;
          };
        };
  };
}
