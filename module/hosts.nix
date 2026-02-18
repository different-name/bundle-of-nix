{
  lib,
  config,
  inputs,
  self,
  ...
}:
let
  inherit (lib) types;
  bundleLib = import ../lib.nix lib;

  cfg = config.bundle;

  allClasses = lib.concatMap lib.attrsToList [
    cfg.systemClasses
    cfg.homeClasses
  ];

  bundleModule = types.submoduleWith {
    description = "Nixxy module";
    class = "bundle";
    specialArgs = { inherit inputs self bundleLib; };

    modules = [
      (
        { bundleInfo, ... }:
        let
          inherit (bundleInfo) system;
          # using custom defined inputs' and self' as using `withSystem` causes infinite recursion
          inputs' = lib.mapAttrs (_: lib.mapAttrs (_: v: v.${system} or v)) inputs;
          self' = inputs'.self;
        in
        {
          _module.args = { inherit inputs' self'; };
        }
      )

      {
        options = lib.listToAttrs (
          map (
            { name, value }:
            lib.nameValuePair value.namespace (
              lib.mkOption {
                type = with lib.types; coercedTo raw lib.toList (listOf raw);
                default = [ ];
                description = "Configuration modules to be imported by ${name}";
                example = lib.literalExpression "{ programs.example.enable = true; }";
              }
            )
          ) allClasses
        );
      }
    ];
  };

  hostUsers = lib.mapAttrs (
    hostAttr: _: lib.filterAttrs (_: user: lib.hasAttr hostAttr user.hosts) cfg.users
  ) cfg.hosts;
in
{
  options.bundle = {
    hosts = lib.mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            system = lib.mkOption {
              type = types.str;
              description = "The architecture of this host";
              example = "x86_64-linux";
            };

            class = lib.mkOption {
              type = types.str;
              description = "The class of this host";
              example = "nixos";
            };
          };
        }
      );
      default = { };
      description = "Host hardware information";
    };

    finalHostConfigs = lib.mkOption {
      type = types.attrsOf bundleModule;
      default = lib.mapAttrs (hostAttr: _: {
        imports =
          lib.concatMap (user: [
            user.hosts.${hostAttr}
            user.shared
          ]) (lib.attrValues hostUsers.${hostAttr})
          ++ [ cfg.shared ];
      }) cfg.hosts;
      internal = true;
      visible = false;
      readOnly = true;
      description = "Host orientated final configuration, only system class configuration will be used from here";
    };

    finalUserConfigs = lib.mkOption {
      type = types.attrsOf (types.attrsOf bundleModule);
      default = lib.mapAttrs (
        hostAttr: _:
        lib.mapAttrs (_: user: {
          imports = [
            user.hosts.${hostAttr}
            user.shared
            cfg.shared
          ];
        }) hostUsers.${hostAttr}
      ) cfg.hosts;
      internal = true;
      visible = false;
      readOnly = true;
      description = "User orientated final configuration, only home class configuration will be used from here";
    };
  };
}
