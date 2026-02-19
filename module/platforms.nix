_:
{
  lib,
  inputs,
  self,
  ...
}:
let
  inherit (lib) types;

  getInput = name: inputs.${name} or (throw "No ${name} input found");

  nixpkgs = getInput "nixpkgs";
  nix-darwin = getInput "nix-darwin";
  home-manager = inputs.home-manager or (throw "No home-manager input found");
  hjem = inputs.hjem or (throw "No hjem input found");

  specialArgs = _: { inherit inputs self; };
  primeArgsConfig =
    { inputs', self', ... }:
    {
      _module.args = { inherit inputs' self'; };
    };
in
{
  options.bundle = {
    systemPlatforms = lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              namespace = lib.mkOption {
                type = types.str;
                default = name;
                description = "Attribute to namespace configuration for this platform under";
                example = "nixos";
              };

              flakeAttribute = lib.mkOption {
                type = types.str;
                description = "Attribute configurations for this platform should be placed under";
                example = "nixosConfigurations";
              };

              mkSystem = lib.mkOption {
                type = types.raw;
                description = "Function to use to create the system configuration";
                example = lib.literalExpression "inputs.nixpkgs.lib.nixosSystem";
              };

              specialArgs = lib.mkOption {
                type = types.raw;
                default = _: { };
                description = ''
                  Function to generate specialArgs for this platform

                  Arguments passed are the same as flake-part's withSystem, with the addition of `host`
                '';
                example = lib.literalExpression ''
                  { inputs, inputs', self, self', ... }:
                  {
                    inherit inputs inputs' self self';
                  }
                '';
              };

              extraConfig = lib.mkOption {
                type = types.raw;
                default = _: { };
                description = ''
                  Function to generate a system-level configuration module for this platform

                  Arguments passed are the same as flake-part's withSystem, with the addition of `host`
                '';
                example = lib.literalExpression ''
                  { host, ... }:
                  {
                    networking.hostName = lib.mkDefault host;
                  };
                '';
              };
            };
          }
        )
      );
      default = { };
      description = "Definition for system platforms, for example: nixos or darwin";
    };

    homePlatforms =
      let
        usersAttrPathOption = {
          type = types.listOf types.str;
          description = "The attribute path from system config to per-user config for this platform";
          example = lib.literalExpression ''
            [ "home-manager" "users" ]
          '';
        };

        extraConfigOption = {
          type = types.raw;
          default = _: { };
          description = ''
            Function to generate a system-level configuration module for this platform

            Arguments passed are the same as flake-part's withSystem, with the addition of `host`
          '';
          example = lib.literalExpression ''
            { inputs, inputs', self, self', ... }:
            {
              home-manager.extraSpecialArgs = { inherit inputs inputs' self self'; };
            }
          '';
        };
      in
      lib.mkOption {
        type = types.attrsOf (
          types.submodule (
            { name, config, ... }:
            {
              options = {
                namespace = lib.mkOption {
                  type = types.str;
                  default = name;
                  description = "Attribute to namespace configuration for this platform under";
                };

                system = {
                  usersAttrPath = lib.mkOption usersAttrPathOption;
                  extraConfig = lib.mkOption extraConfigOption;

                  platforms = lib.mkOption {
                    type = types.attrsOf (
                      types.submodule {
                        options = {
                          module = lib.mkOption {
                            type = types.deferredModule;
                            description = "The system module to import for this home-platform";
                            example = lib.literalExpression "inputs.home-manager.nixosModules.default";
                          };

                          usersAttrPath = lib.mkOption (usersAttrPathOption // { default = config.system.usersAttrPath; });
                          extraConfig = lib.mkOption (extraConfigOption // { default = config.system.extraConfig; });
                        };
                      }
                    );
                    default = { };
                    description = "Required configuration for each system-platform";
                  };
                };

                extraHomeConfig = lib.mkOption {
                  type = types.raw;
                  default = _: { };
                  description = ''
                    Function to generate a home-level configuration module for this platform

                    Arguments passed are the same as flake-part's withSystem, with the addition of `host` and `user`
                  '';
                  example = lib.literalExpression ''
                    { user, ... }:
                    {
                      home = {
                        username = lib.mkDefault user;
                        homeDirectory = lib.mkDefault "/home/''${user}";
                      };
                    }
                  '';
                };
              };
            }
          )
        );
        default = { };
        description = "Definition for home platforms, for example: home-manager or hjem";
      };
  };

  config.bundle = {
    systemPlatforms = {
      nixos = {
        mkSystem = nixpkgs.lib.nixosSystem;
        inherit specialArgs;
        extraConfig = primeArgsConfig;
        flakeAttribute = "nixosConfigurations";
      };

      darwin = {
        mkSystem = nix-darwin.lib.darwinSystem;
        inherit specialArgs;
        extraConfig = primeArgsConfig;
        flakeAttribute = "darwinConfigurations";
      };
    };

    homePlatforms = {
      home-manager = {
        system = {
          usersAttrPath = [
            "home-manager"
            "users"
          ];

          extraConfig = _: {
            home-manager.extraSpecialArgs = { inherit inputs self; };
          };

          platforms = {
            nixos.module = home-manager.nixosModules.default;
            darwin.module = home-manager.darwinModules.default;
          };
        };

        extraHomeConfig = primeArgsConfig;
      };

      hjem = {
        system = {
          usersAttrPath = [
            "hjem"
            "users"
          ];

          extraConfig = _: { hjem = { inherit specialArgs; }; };

          platforms = {
            nixos.module = hjem.nixosModules.default;
            darwin.module = hjem.darwinModules.default;
          };
        };

        extraHomeConfig = primeArgsConfig;
      };
    };
  };
}
