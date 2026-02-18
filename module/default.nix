{
  lib,
  config,
  getSystem,
  ...
}:
let
  bundleLib = import ../lib.nix { inherit lib getSystem; };

  inherit (lib) types;
  inherit (bundleLib) transpose withSystemExtraArgs;

  cfg = config.bundle;
in
{
  imports = map (module: import module bundleLib) [
    ./classes.nix
    ./hosts.nix
    ./users.nix
  ];

  options.bundle = {
    specialArgs = lib.mkOption {
      type = types.attrs;
      default = { };
      example = lib.literalExpression "{ inherit veryYippieLib; }";
      description = "`specialArgs` passed to bundle. This option can be used to pass additional arguments to all bundle modules";
    };

    shared = lib.mkOption {
      type = types.deferredModule;
      default = { };
      description = "Bundle configuration shared between all users and their hosts";
    };
  };

  config.flake =
    let
      hostConfigurations = lib.mapAttrs (
        hostAttr: host:
        let
          # complete bundled configuration for this host
          sysBundle = cfg.bundlesByHost.${hostAttr};
          # complete bundled configurations for each user of this host
          homeBundles = cfg.bundlesByHostUser.${hostAttr};

          sysClassAttr = host.class;
          sysClass = cfg.systemClasses.${sysClassAttr} or (throw "No '${sysClassAttr}' system class found");

          specialArgs = withSystemExtraArgs host.system { host = hostAttr; } sysClass.specialArgs;
          sysModules =
            let
              extraConfig = withSystemExtraArgs host.system { host = hostAttr; } sysClass.extraConfig;
            in
            [ extraConfig ] ++ sysBundle.${sysClass.namespace};

          # home classes that are in use, and have a usable module
          usedHomeClasses = lib.filter (
            homeClass:
            let
              # does the home class have any configuration for this host?
              isUsed = sysBundle.${homeClass.namespace} != [ ];
              # does the home class provide a module for this system class?
              hasSystemModule = lib.hasAttr sysClassAttr homeClass.system.classes;
            in
            isUsed && hasSystemModule
          ) (lib.attrValues cfg.homeClasses);

          # configuration modules to import for home class -> user
          # transposed from cfg.bundlesByHostUser.<host>
          modulesByHomeClassUser = transpose homeBundles;

          # system modules from each home class that is in use
          # this includes the system module & extraConfig for the home class itself e.g.
          #   inputs.home-manager.nixosModules.default
          # as well as home level imports & extraHomeConfig mapped to system config e.g.
          #   { home-manager.users.diffy.imports = [ { home.username = "diffy"; } ]; }
          sysModulesFromHomeClasses = lib.concatMap (
            homeClass:
            let
              sysModule = homeClass.system.classes.${sysClassAttr}.module;

              extraConfig = withSystemExtraArgs host.system {
                host = hostAttr;
              } homeClass.system.extraConfig;

              inherit (homeClass.system.classes.${sysClassAttr}) usersAttrPath;
              homeModulesByUser = modulesByHomeClassUser.${homeClass.namespace};

              mappedHomeModules = lib.mapAttrsToList (
                userAttr: homeModules:
                let
                  extraHomeConfig = withSystemExtraArgs host.system {
                    host = hostAttr;
                    user = userAttr;
                  } homeClass.extraHomeConfig;
                in
                lib.setAttrByPath usersAttrPath {
                  ${userAttr}.imports = [ extraHomeConfig ] ++ homeModules;
                }
              ) homeModulesByUser;
            in
            [
              sysModule
              extraConfig
            ]
            ++ mappedHomeModules
          ) usedHomeClasses;
        in
        {
          inherit sysClass;

          args = {
            inherit specialArgs;
            modules = sysModules ++ sysModulesFromHomeClasses;
          };
        }
      ) cfg.hosts;

      # final generated configurations, each placed under <sysClass.flakeAttribute>.<host>
      configurations = transpose (
        lib.mapAttrs (
          _: hostConfiguration:
          let
            inherit (hostConfiguration) sysClass args;
          in
          {
            ${sysClass.flakeAttribute} = sysClass.mkSystem args;
          }
        ) hostConfigurations
      );
    in
    configurations;
}
