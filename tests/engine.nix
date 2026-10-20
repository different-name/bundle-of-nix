{ lib }:
let
  bundleModule = import ../module;

  stubInputs = {
    self = { };
  };

  stubEnv = {
    options.flake = lib.mkOption { type = lib.types.raw; };
    config._module.args = {
      inputs = stubInputs;
      inherit (stubInputs) self;
      # the engine only ever reaches into `allModuleArgs`
      getSystem = _: {
        allModuleArgs = {
          inputs = stubInputs;
          inherit (stubInputs) self;
          inputs' = stubInputs;
          self' = stubInputs.self;
        };
      };
    };
  };

  # mkSystem echoes its args so the assembled modules can be inspected
  stubPlatform = {
    bundle.systemPlatforms.stub = {
      flakeAttribute = "stubConfigurations";
      mkSystem = args: { inherit args; };
      specialArgs = { host, ... }: { inherit host; };
      extraConfig = _: { platformBit = true; };
    };
  };

  evalWith =
    bundleConfig:
    lib.evalModules {
      modules = [
        bundleModule
        stubEnv
        stubPlatform
        { inherit (bundleConfig) bundle; }
      ];
    };

  good = evalWith {
    bundle = {
      hosts.alpha = {
        system = "x86_64-linux";
        systemPlatform = "stub";
      };
      users.me = {
        shared.stub.sharedBit = true;
        hosts.alpha.stub.hostBit = true;
      };
    };
  };

  alpha = good.config.flake.stubConfigurations.alpha or null;

  bad = evalWith {
    bundle = {
      hosts.alpha = {
        system = "x86_64-linux";
        systemPlatform = "stub";
      };
      users.me.hosts.ghost.stub.oops = true;
    };
  };

  badThrows = !(builtins.tryEval bad.config.flake).success;

  host = {
    system = "x86_64-linux";
    systemPlatform = "stub";
  };

  evalSystem =
    configuration:
    (lib.evalModules {
      modules = [
        { _module.freeformType = lib.types.attrsOf lib.types.anything; }
      ]
      ++ configuration.args.modules;
    }).config;

  feature =
    { bundleLib, config, ... }:
    bundleLib.mkEnableModule [ "feature" ] {
      options.knob = lib.mkOption {
        type = lib.types.str;
        default = "unset";
      };
      imports = [ { stub.importedBit = true; } ];
      stub.knob = config.feature.knob;
    };

  features = evalWith {
    bundle = {
      hosts = {
        on = host;
        off = host;
      };
      users.me = {
        shared = feature;
        hosts.on.feature = {
          enable = true;
          knob = "set";
        };
        hosts.off.feature.knob = "set";
      };
    };
  };

  featureOn = evalSystem features.config.flake.stubConfigurations.on;
  featureOff = evalSystem features.config.flake.stubConfigurations.off;

  attached = evalWith {
    bundle = {
      hosts.alpha = host;
      systemPlatforms.stub.extraConfig = { host, ... }: { extraHost = host; };
      homePlatforms.home-manager = {
        attachTo.stub.module = { };
        extraHomeConfig = _: { };
      };
      users.me.hosts.alpha =
        { bundleInfo, ... }:
        {
          stub.info = bundleInfo;
          home-manager.info = bundleInfo;
        };
    };
  };

  attachedAlpha = attached.config.flake.stubConfigurations.alpha;
  attachedSystem = evalSystem attachedAlpha;
  homeImports =
    (lib.findFirst (module: module ? home-manager.users) { } attachedAlpha.args.modules)
    .home-manager.users.me.imports;

  unattached = evalWith {
    bundle = {
      hosts.alpha = host;
      users.me.hosts.alpha.home-manager.homeBit = true;
    };
  };

  cases = [
    {
      name = "generates <flakeAttribute>.<host>";
      ok = good.config.flake ? stubConfigurations.alpha;
    }
    {
      name = "specialArgs carries the host name";
      ok = (alpha.args.specialArgs.host or null) == "alpha";
    }
    {
      name = "collects system modules as a list";
      ok = alpha != null && builtins.isList alpha.args.modules;
    }
    {
      name = "merges shared + host-specific system config";
      ok =
        let
          flat = lib.foldl' (a: m: a // m) { } alpha.args.modules;
        in
        (flat.sharedBit or false) && (flat.hostBit or false);
    }
    {
      name = "throws on a user referencing an undeclared host";
      ok = badThrows;
    }
    {
      name = "mkEnableModule declares extra options beside enable";
      ok = featureOn.knob == "set";
    }
    {
      name = "mkEnableModule options exist while disabled";
      ok = !(featureOff ? knob);
    }
    {
      name = "mkEnableModule imports apply regardless of enable";
      ok = (featureOn.importedBit or false) && (featureOff.importedBit or false);
    }
    {
      name = "bundleInfo carries the host name";
      ok =
        attachedSystem.info == {
          system = "x86_64-linux";
          host = "alpha";
        };
    }
    {
      name = "bundleInfo carries the user name in home config";
      ok = lib.elem {
        info = {
          system = "x86_64-linux";
          host = "alpha";
          home.user = "me";
        };
      } homeImports;
    }
    {
      name = "extraConfig definitions merge";
      ok = attachedSystem.platformBit && attachedSystem.extraHost == "alpha";
    }
    {
      name = "extraHomeConfig definitions merge";
      ok = lib.length (lib.head homeImports).imports == 2;
    }
    {
      name = "builds a host with no home config and no home module";
      ok = (builtins.tryEval alpha).success;
    }
    {
      name = "throws on home config with no module for the system-platform";
      ok = !(builtins.tryEval unattached.config.flake.stubConfigurations.alpha).success;
    }
  ];

  failures = lib.filter (c: !c.ok) cases;
in
if failures == [ ] then
  "ok: ${toString (lib.length cases)} bundle engine tests passed"
else
  throw "bundle engine tests failed: ${lib.concatMapStringsSep ", " (c: c.name) failures}"
