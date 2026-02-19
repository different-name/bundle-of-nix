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
    ./platforms.nix
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

          sysPlatformAttr = host.systemPlatform;
          sysPlatform =
            cfg.systemPlatforms.${sysPlatformAttr} or (throw "No '${sysPlatformAttr}' system-platform found");

          specialArgs = withSystemExtraArgs host.system { host = hostAttr; } sysPlatform.specialArgs;
          sysModules =
            let
              extraConfig = withSystemExtraArgs host.system { host = hostAttr; } sysPlatform.extraConfig;
            in
            [ extraConfig ] ++ sysBundle.${sysPlatform.namespace};

          # home-platforms that are in use, and have a usable module
          usedHomePlatforms = lib.filter (
            homePlatform:
            let
              # does the home-platform have any configuration for this host?
              isUsed = sysBundle.${homePlatform.namespace} != [ ];
              # does the home-platform provide a module for this system-platform?
              hasSystemModule = lib.hasAttr sysPlatformAttr homePlatform.system.platforms;
            in
            isUsed && hasSystemModule
          ) (lib.attrValues cfg.homePlatforms);

          # configuration modules to import for home-platform -> user
          # transposed from cfg.bundlesByHostUser.<host>
          modulesByHomePlatformUser = transpose homeBundles;

          # system modules from each home-platform that is in use
          # this includes the system module & extraConfig for the home-platform itself e.g.
          #   inputs.home-manager.nixosModules.default
          # as well as home level imports & extraHomeConfig mapped to system config e.g.
          #   { home-manager.users.diffy.imports = [ { home.username = "diffy"; } ]; }
          sysModulesFromHomePlatforms = lib.concatMap (
            homePlatform:
            let
              sysModule = homePlatform.system.platforms.${sysPlatformAttr}.module;

              extraConfig = withSystemExtraArgs host.system {
                host = hostAttr;
              } homePlatform.system.extraConfig;

              inherit (homePlatform.system.platforms.${sysPlatformAttr}) usersAttrPath;
              homeModulesByUser = modulesByHomePlatformUser.${homePlatform.namespace};

              mappedHomeModules = lib.mapAttrsToList (
                userAttr: homeModules:
                let
                  extraHomeConfig = withSystemExtraArgs host.system {
                    host = hostAttr;
                    user = userAttr;
                  } homePlatform.extraHomeConfig;
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
          ) usedHomePlatforms;
        in
        {
          inherit sysPlatform;

          args = {
            inherit specialArgs;
            modules = sysModules ++ sysModulesFromHomePlatforms;
          };
        }
      ) cfg.hosts;

      # final generated configurations, each placed under <sysPlatform.flakeAttribute>.<host>
      configurations = transpose (
        lib.mapAttrs (
          _: hostConfiguration:
          let
            inherit (hostConfiguration) sysPlatform args;
          in
          {
            ${sysPlatform.flakeAttribute} = sysPlatform.mkSystem args;
          }
        ) hostConfigurations
      );
    in
    configurations;
}
