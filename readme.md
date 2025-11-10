Adding tools like `print` while extending `nixpkgs.lib` and `flake-utils` for a one-stop helper library.

```nix
{
    description = "";
    inputs = {
        lib.url = "github:jeff-hykin/quick-nix-toolkits";
    };
    outputs = { self, lib, ... }:
        lib.eachSystem lib.defaultSystems (system:
            let
                builtins = lib.builtins;
                pkgs = import nixpkgs { inherit system; };
                
                _ = lib.print { prefix = "lib version"; val = lib.version; } lib;
                
                jsonData = _.readJson ./package.json;
                tomlData = _.readToml ./package.toml;
                
                someAttrSet = { a={b={c=1;};}; };
                c = _.getDeepAttributeSafely someAttrSet [ "a" "b" "c" ];
                f = _.getDeepAttributeSafely someAttrSet [ "a" "b" "f" ]; # null
                
                # keep your package-related logic closely coupled 
                # keep inputs flat then query them for mkShell or mkDerivation
                aggregation = lib.aggregator [
                    # easy packages
                    { vals.pkg=pkgs.android-tools; }
                    { vals.pkg=pkgs.esbuild; }
                    { vals.pkg=pkgs.zip;     }
                    { vals.pkg=pkgs.unzip;   }
                    { vals.pkg=pkgs.less;    }
                    
                    # package that has associated shellHook code
                    {
                        vals.pkg=pkgs.nodejs;
                        
                        # node-js related hook
                        vals.shellHook = ''
                            # without this npm (from nix) will not keep a reliable cache (it'll be outside of the xome home)
                            export npm_config_cache="$HOME/.cache/npm"
                            ! [ -d "node_modules" ] && npm install  
                        '';
                    }
                    
                    # sh (from dash)
                    {
                        vals.pkg=pkgs.dash;
                        
                        # provide "sh" cause lots of things need sh
                        vals.shellHook = ''
                            ln -s "$(which dash)" "$HOME/.local/bin/sh" 2>/dev/null
                        '';
                    }
                    
                    # dev-shell packages
                    { vals.devShellPkg=pkgs.htop;      }
                    { vals.devShellPkg=pkgs.ripgrep;   }
                    { vals.devShellPkg=pkgs.findutils; }
                
                    # packages that need to be grouped (use flags)
                    { vals.pkg=pkgs.python313Packages.numpy;      flags.isPythonPackage=true; }
                    { vals.pkg=pkgs.python313Packages.opencv;     flags.isPythonPackage=true; }
                    { vals.pkg=pkgs.python313Packages.matplotlib; flags.isPythonPackage=true; }
                    
                    # custom handling
                    ({ prevVals, getAll, ... }: {
                        vals.pkg=python3.withPackages (getAll { flags=[ "isPythonPackage" ]; attrPath=[ "pkg" ]; });
                    })
                ];
                buildInputs = aggregation.getAll { attrPath=[ "pkg" ]; };
                shellHook   = aggregation.getAll { attrPath=[ "shellHook" ]; strJoin="\n"; };
                devShellInputs = buildInputs ++ aggregation.getAll { attrPath=["devShellPkg"]; };
            in
                {
                    # your code here
                }
        )
    ;
}
```