{
  description = "Tests, checks and formatting for bundle-of-nix";

  # the library reads its inputs from the consumer, this flake supplies them for the tests
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bundle.url = "path:..";
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      bundle,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { lib, ... }:
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ];

        # a nested flake keeps the example host out of nixosConfigurations, which nix flake check would build
        flake.checks.x86_64-linux.integration =
          let
            pkgs = nixpkgs.legacyPackages.x86_64-linux;

            example = flake-parts.lib.mkFlake { inherit inputs; } {
              systems = [ "x86_64-linux" ];
              imports = [ bundle.flakeModules.default ];

              bundle = {
                hosts.testhost = {
                  system = "x86_64-linux";
                  systemPlatform = "nixos";
                };

                hosts.foreignbox.system = "x86_64-linux";

                systemPlatforms.nixos.extraConfig =
                  { host, ... }:
                  {
                    environment.etc."extra-config-host".text = host;
                  };

                users.alice = {
                  shared = {
                    imports = [
                      (
                        { bundleInfo, ... }:
                        {
                          nixos.environment.etc."bundle-host".text = bundleInfo.host;
                          home-manager.home.sessionVariables.BUNDLE_USER = bundleInfo.home.user;
                        }
                      )
                    ];

                    nixos.system.stateVersion = "24.11";
                    home-manager.home.stateVersion = "24.11";
                  };

                  hosts.testhost = {
                    nixos = {
                      networking.hostName = "testhost";
                      users.users.alice = {
                        isNormalUser = true;
                        home = "/home/alice";
                      };
                    };
                    home-manager.home = {
                      username = "alice";
                      homeDirectory = "/home/alice";
                    };
                  };

                  hosts.foreignbox.home-manager.home.homeDirectory = "/home/alice";
                };

                users.bob.hosts.testhost.nixos.users.users.bob.isNormalUser = true;
              };
            };

            sys = example.nixosConfigurations.testhost.config;
            home = example.homeConfigurations."alice@foreignbox".config;

            cases = {
              "home-manager is wired under the user" = sys.home-manager.users ? alice;
              "home config is routed to the user" = sys.home-manager.users.alice.home.username == "alice";
              "host-specific nixos config is applied" = sys.networking.hostName == "testhost";
              "shared nixos config is merged in" = sys.system.stateVersion == "24.11";
              "host platform is set from the host's system" = sys.nixpkgs.hostPlatform.system == "x86_64-linux";
              "extraConfig merges with the platform's own" =
                sys.environment.etc."extra-config-host".text == "testhost";
              "bundleInfo carries the host name" = sys.environment.etc."bundle-host".text == "testhost";
              "bundleInfo carries the user name" =
                sys.home-manager.users.alice.home.sessionVariables.BUNDLE_USER == "alice";
              "the system user account is present" = sys.users.users ? alice;
              "a user without home config gets no home-manager entry" = !(sys.home-manager.users ? bob);
              "system-less host builds a standalone home configuration" =
                example.homeConfigurations ? "alice@foreignbox";
              "standalone home username defaults to the user" = home.home.username == "alice";
              "shared home config is merged into the standalone build" = home.home.stateVersion == "24.11";
              "system-ful host does not emit a standalone home configuration" =
                !(example.homeConfigurations ? "alice@testhost");
            };

            failures = lib.filter (name: !cases.${name}) (lib.attrNames cases);
          in
          if failures == [ ] then
            pkgs.runCommandLocal "bundle-integration-eval" { } "echo ok > $out"
          else
            throw "bundle integration checks failed: ${lib.concatStringsSep ", " failures}";

        perSystem =
          { pkgs, ... }:
          {
            formatter = pkgs.nixfmt;

            checks.engine =
              pkgs.runCommandLocal "bundle-engine-test"
                { result = import "${bundle}/tests/engine.nix" { inherit (pkgs) lib; }; }
                ''
                  echo "$result" > $out
                '';

            devShells.default = pkgs.mkShell {
              packages = [ pkgs.nixfmt ];
            };
          };
      }
    );
}
