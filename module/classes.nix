{ ... }:
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
    systemClasses = lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              namespace = lib.mkOption {
                type = types.str;
                default = name;
                description = "Attribute to namespace configuration for this class under";
                example = "nixos";
              };

              flakeAttribute = lib.mkOption {
                type = types.str;
                description = "Attribute configurations for this class should be placed under";
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
                  Function to generate specialArgs for this class

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
                  Function to generate a system-level configuration module for this class

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
      description = ''
        Definition for system classes, a system class is a host level configuration

        For example: nixos or darwin
      '';
    };

    homeClasses =
      let
        usersAttrPathOption = {
          type = types.listOf types.str;
          description = "The attribute path from system config to per-user config for this class";
          example = lib.literalExpression ''
            [ "home-manager" "users" ]
          '';
        };

        extraConfigOption = {
          type = types.raw;
          default = _: { };
          description = ''
            Function to generate a system-level configuration module for this class

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
                  description = "Attribute to namespace configuration for this class under";
                };

                system = {
                  usersAttrPath = lib.mkOption usersAttrPathOption;
                  extraConfig = lib.mkOption extraConfigOption;

                  classes = lib.mkOption {
                    type = types.attrsOf (
                      types.submodule {
                        options = {
                          module = lib.mkOption {
                            type = types.deferredModule;
                            description = "The system module to import for this home class";
                            example = lib.literalExpression "inputs.home-manager.nixosModules.default";
                          };

                          usersAttrPath = lib.mkOption (usersAttrPathOption // { default = config.system.usersAttrPath; });
                          extraConfig = lib.mkOption (extraConfigOption // { default = config.system.extraConfig; });
                        };
                      }
                    );
                    default = { };
                    description = "Required configuration for each system class";
                  };
                };

                extraHomeConfig = lib.mkOption {
                  type = types.raw;
                  default = _: { };
                  description = ''
                    Function to generate a home-level configuration module for this class

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
        description = ''
          Definition for home classes, a home class is a user level configuration

          For example: home-manager or hjem
        '';
      };
  };

  config.bundle = {
    systemClasses = {
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

    homeClasses = {
      home-manager = {
        system = {
          usersAttrPath = [
            "home-manager"
            "users"
          ];

          extraConfig = _: {
            home-manager.extraSpecialArgs = { inherit inputs self; };
          };

          classes = {
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

          classes = {
            nixos.module = hjem.nixosModules.default;
            darwin.module = hjem.darwinModules.default;
          };
        };

        extraHomeConfig = primeArgsConfig;
      };
    };
  };
}
