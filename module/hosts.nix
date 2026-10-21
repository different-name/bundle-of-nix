bundleLib:
{
  lib,
  config,
  inputs,
  self,
  ...
}:
let
  inherit (lib) types;

  cfg = config.bundle;

  allPlatforms = lib.concatMap lib.attrsToList [
    cfg.systemPlatforms
    cfg.homePlatforms
  ];

  bundleModule = types.submoduleWith {
    description = "Nixxy module";
    class = "bundle";
    specialArgs = {
      inherit inputs self bundleLib;
    }
    // cfg.specialArgs;

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
          ) allPlatforms
        );
      }

      {
        options.homePlatforms = lib.mapAttrs' (
          name: platform:
          lib.nameValuePair platform.namespace {
            enable = lib.mkOption {
              type = types.bool;
              default = true;
              description = "Whether ${name} is used by this user on this host. Its modules are dropped when false. In host-level configuration it is true when any user has it enabled";
            };
          }
        ) cfg.homePlatforms;
      }
    ];
  };

  usersByHost = lib.mapAttrs (
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

            systemPlatform = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "The system platform of this host, or null for a system-less host that only builds standalone home configurations";
              example = "nixos";
            };
          };
        }
      );
      default = { };
      description = "Host hardware information";
    };

    bundlesByHost = lib.mkOption {
      type = types.attrsOf bundleModule;
      default = lib.mapAttrs (hostAttr: host: {
        _module.args.bundleInfo = {
          inherit (host) system;
          host = hostAttr;
        };

        homePlatforms = lib.mapAttrs' (
          _: platform:
          lib.nameValuePair platform.namespace {
            enable = lib.mkForce (
              lib.any (bundle: bundle.homePlatforms.${platform.namespace}.enable) (
                lib.attrValues cfg.bundlesByHostUser.${hostAttr}
              )
            );
          }
        ) cfg.homePlatforms;

        imports =
          let
            userBundles = lib.concatMap (user: [
              user.hosts.${hostAttr}
              user.shared
            ]) (lib.attrValues usersByHost.${hostAttr});
          in
          [ cfg.shared ] ++ userBundles;
      }) cfg.hosts;
      internal = true;
      visible = false;
      readOnly = true;
      description = ''
        Host orientated final configuration, only system-platform configuration will be used from here

        This data is structured like so:

        <host>.<platform> = modules

        ```nix
        {
          host-1 = {
            nixos = [ ... ];
            darwin = [ ... ];
            home-manager = [ ... ]; # unused
            hjem = [ ... ];         # unused
          };
          host-2 = { << repeated >> };
        };
        ```
      '';
    };

    bundlesByHostUser = lib.mkOption {
      type = types.attrsOf (types.attrsOf bundleModule);
      default = lib.mapAttrs (
        hostAttr: host:
        lib.mapAttrs (userAttr: user: {
          _module.args.bundleInfo = {
            inherit (host) system;
            host = hostAttr;
            home.user = userAttr;
          };

          imports = [
            user.hosts.${hostAttr}
            user.shared
            cfg.shared
          ];
        }) usersByHost.${hostAttr}
      ) cfg.hosts;
      internal = true;
      visible = false;
      readOnly = true;
      description = ''
        Home-platform orientated final configuration, only home-platform configuration will be used from here

        This data is structured like so:

        <host>.<user>.<platform> = modules

        ```nix
        {
          host-1 = {
            user-1 = {
              home-manager = [ ... ];
              hjem = [ ... ];
              nixos = [ ... ];  # unused
              darwin = [ ... ]; # unused
            };
            user-1 = { << repeated >> };
          };
        };
        ```
      '';
    };
  };
}
