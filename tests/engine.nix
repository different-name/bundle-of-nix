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
  ];

  failures = lib.filter (c: !c.ok) cases;
in
if failures == [ ] then
  "ok: ${toString (lib.length cases)} bundle engine tests passed"
else
  throw "bundle engine tests failed: ${lib.concatMapStringsSep ", " (c: c.name) failures}"
