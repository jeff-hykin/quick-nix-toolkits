{
    description = "Toolbox for generic nix helper functions";
    inputs = {
        libSource.url = "github:nix-community/nixpkgs.lib";
        flakeUtils.url = "github:numtide/flake-utils";
        # core.url = "path:./helpers/builtins"; # for overriding builtins
    };
    outputs = { self, libSource, flakeUtils, ... }:
        let
            # builtins = core; # lets builtins be overridden by others
            # maintainers and teams fail to evaluate when from the pure "nixpkgs.lib" repo
            # overriding them means the lib isn't going to throw an error now 
            lib = libSource.lib // {
                maintainers = {};
                teams = {}; 
            };
            isUrl = (str:
                builtins.any (prefix: builtins.hasPrefix prefix str) [
                    "http://"
                    "https://"
                    "ftp://"
                    "file://"
                ]
            );
            readJson = path: builtins.fromJSON (builtins.readFile path);
            readToml = path: builtins.fromTOML (builtins.readFile path);
            noValue = { a= b: b; }; # attrsets that contain functions as values will return false when compared to anything other than itself
            # we can use this as a means of checking non-provided-values in contrast to null values 
            
            # prefixing a trace is harder than you think because of additional traces that happen when evaluating the value
            # (thus making prints appear out of order)
            # this print function tries to fix that
            # Usage:
            #     print { prefix = "prefix"; val = value; } "return value"
            #     print "something"
            print = (input1: returnValue:
                let
                    input1IsAttrs = builtins.isAttrs input1;  
                    prefix = if input1IsAttrs then input1.prefix or null else input1;
                    postfix = if input1IsAttrs then input1.postfix or null else null;
                    val = if input1IsAttrs then input1.val or noValue else noValue;
                    
                    printValue = if val == noValue then returnValue else val;
                    ending = (builtins.trace
                        printValue
                        (if postfix == null then
                            returnValue
                        else
                            (builtins.trace
                                postfix
                                returnValue
                            )
                        )
                    );
                in
                    if prefix == null then
                        ending
                    else
                        (builtins.trace
                            (if (builtins.tryEval printValue).success then
                                prefix+":"
                            else
                                returnValue # if it fails its going to throw anyways and not get here
                            )
                            ending
                        )
            );
            hasDeepAttribute = (
                let
                    hasDeepAttributeInner = (attrSet: path:
                        (builtins.foldl'
                            (acc: key:
                                if acc != null && builtins.isAttrs acc && builtins.hasAttr key acc then
                                    acc.${key}
                                else
                                    null
                            )
                            attrSet
                            (if (path != null && builtins.isList path) then path else [])
                        )
                    );
                in
                    # Final result is: was the value resolved to something non-null?
                    attrSet: path: hasDeepAttributeInner attrSet path != null
            );
            getDeepAttribute = (attrSet: path:
                (builtins.foldl'
                    (acc: key:
                        if acc != null && builtins.isAttrs acc && builtins.hasAttr key acc then
                            acc.${key}
                        else
                            null
                    )
                    attrSet
                    path
                )
            );
            getDeepAttributeSafely = (attrSet: path:
                if hasDeepAttribute attrSet path then
                    getDeepAttribute attrSet path
                else
                    null
            );
            canBeNicelyCorcedToString = (val: # note: builtins.isList is intentionally not included here. 
                builtins.isString val || builtins.isPath val || (val ? outPath) && builtins.isString val.outPath || builtins.isFloat val || builtins.isInt val || val == null
            );
            
            # example of aggregator usage:
            #     devInputs = aggregator [
            #         # project info
            #         { 
            #             vals.config.name = projectJson.name;
            #             vals.config.version = projectJson.version;
            #         }
            #     
            #         # main packages
            #         { vals.pkg=pkgs.android-tools; }
            #         { vals.pkg=pkgs.esbuild; }
            #         { vals.pkg=pkgs.zip;     }
            #         { vals.pkg=pkgs.unzip;   }
            #         { vals.pkg=pkgs.less;    }
            #         {
            #             vals.pkg=pkgs.nodejs;
            #             vals.devShellHook = ''
            #                 # without this npm (from nix) will not keep a reliable cache (it'll be outside of the xome home)
            #                 export npm_config_cache="$HOME/.cache/npm"
            #     
            #                 # 
            #                 # offer to run npm install
            #                 # 
            #                 if ! [ -d "node_modules" ]
            #                 then
            #                     question="I don't see node_modules, should I run npm install? [y/n]";answer=""
            #                     while true; do
            #                         echo "$question"; read response
            #                         case "$response" in
            #                             [Yy]* ) answer='yes'; break;;
            #                             [Nn]* ) answer='no'; break;;
            #                             * ) echo "Please answer yes or no.";;
            #                         esac
            #                     done
            #     
            #                     if [ "$answer" = 'yes' ]; then
            #                         npm install
            #                     fi
            #                 fi
            #             '';
            #         }
            #     
            #         # core devshell stuff
            #         { vals.devShellPkg=pkgs.coreutils-full;     }
            #         {
            #             vals.devShellPkg=pkgs.dash;
            #             # provide "sh" cause lots of things need sh
            #             vals.devShellHook = ''
            #                 ln -s "$(which dash)" "$HOME/.local/bin/sh" 2>/dev/null
            #             '';
            #         }
            #         # optional but handy dev-shell stuff
            #         { vals.devShellPkg=pkgs.gnugrep;            }
            #         { vals.devShellPkg=pkgs.findutils;          }
            #         { vals.devShellPkg=pkgs.wget;               }
            #         { vals.devShellPkg=pkgs.curl;               }
            #         { vals.devShellPkg=pkgs.unixtools.locale;   }
            #         { vals.devShellPkg=pkgs.unixtools.more;     }
            #         { vals.devShellPkg=pkgs.unixtools.ps;       }
            #         { vals.devShellPkg=pkgs.unixtools.getopt;   }
            #         { vals.devShellPkg=pkgs.unixtools.ifconfig; }
            #         { vals.devShellPkg=pkgs.unixtools.hostname; }
            #         { vals.devShellPkg=pkgs.unixtools.ping;     }
            #         { vals.devShellPkg=pkgs.unixtools.hexdump;  }
            #         { vals.devShellPkg=pkgs.unixtools.killall;  }
            #         { vals.devShellPkg=pkgs.unixtools.mount;    }
            #         { vals.devShellPkg=pkgs.unixtools.sysctl;   }
            #         { vals.devShellPkg=pkgs.unixtools.top;      }
            #         { vals.devShellPkg=pkgs.unixtools.umount;   }
            #         { vals.devShellPkg=pkgs.git;                }
            #         { vals.devShellPkg=pkgs.htop;               }
            #         { vals.devShellPkg=pkgs.ripgrep;            }
            #     
            #         # 
            #         # Linux stuff
            #         # 
            #         { vals.pkg=pkgs.gcc;        onlyIf=pkgs.stdenv.isLinux; }
            #         { vals.pkg=pkgs.dpkg;       onlyIf=pkgs.stdenv.isLinux; }
            #         { vals.pkg=pkgs.fakeroot;   onlyIf=pkgs.stdenv.isLinux; }
            #         { vals.pkg=pkgs.rpm;        onlyIf=pkgs.stdenv.isLinux; }
            #         { vals.pkg=pkgs.pkg-config; onlyIf=pkgs.stdenv.isLinux; }
            #     
            #         # main inputs (sections below this, ex: dbus, are discovered from stuff like atk)
            #         { vals.pkg=pkgs.atk.dev;                          onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.gdk-pixbuf.dev;                   onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.gtk3.dev;                         onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.pango.dev;                        onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libayatana-appindicator-gtk3.dev; onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.glib.dev;                         onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #     
            #         # discovered needed inputs
            #         { vals.pkg=pkgs.dbus.dev;             onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libpng.dev;           onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libjpeg.dev;          onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libtiff.dev;          onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.cairo.dev;            onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.fribidi.dev;          onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.fontconfig.dev;       onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.harfbuzz.dev;         onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libthai.dev;          onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.freetype.dev;         onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.xorg.libXrender.dev;  onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.xorg.libXft.dev;      onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.zlib;                 onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.zlib.dev;             onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libffi.dev;           onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libselinux.dev;       onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.expat.dev;            onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.graphite2.dev;        onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.bzip2.dev;            onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.lerc.dev;             onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libsepol.dev;         onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #     
            #         # libs not even on the list, but needed at link time 
            #         { vals.pkg=pkgs.json-glib;      onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libselinux;     onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.wayland;        onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libjson;        onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.tinysparql;     onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.tinysparql.dev; onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.json-glib.dev;  onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.libselinux.dev; onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #         { vals.pkg=pkgs.wayland.dev;    onlyIf=pkgs.stdenv.isLinux; flags.forPkgConfig=true; }
            #     
            #         # on linux, everthing for pkg-config needs to be added to PKG_CONFIG_PATH, LIBRARY_PATH, etc
            #         ({ prevVals, prevAttrsets, mergedVals, getAll, errorIndex }:
            #             let 
            #                 pkgsForPkgConfigTool = getAll { hasAllFlags = ["forPkgConfig"]; attrPath = [ "pkg" ]; };
            #             in
            #                 {
            #                     onlyIf=pkgs.stdenv.isLinux;
            #                     vals.shellHook = ''
            #                         export PKG_CONFIG_PATH=${lib.escapeShellArg (builtins.concatStringsSep ":" (map (x: "${x}/lib/pkgconfig") pkgsForPkgConfigTool))}
            #                         export LD_LIBRARY_PATH=${lib.escapeShellArg (builtins.concatStringsSep ":" (map (x: "${x}/lib") pkgsForPkgConfigTool))}
            #                         export LIBRARY_PATH=${lib.escapeShellArg (builtins.concatStringsSep ":" (map (x: "${x}/lib") pkgsForPkgConfigTool))}
            #                     '';
            #                 }
            #         )
            #     ];
            aggregator = (list:
                let
                    # Recursive element processor
                    process = (runningVals: parentIndex: elems:
                        lib.foldl'
                            (acc: elem:
                                let
                                    run = acc.runningVals;
                                    idx = acc.currentErrorIndex;
                                    err = msg: throw "Error when calling aggregator, coming from item with errorIndex ${idx}: ${msg}";

                                    # Helper for building new runningVals
                                    advance = newRun: nextIndex:
                                        { runningVals = newRun; currentErrorIndex = nextIndex; };

                                    # Helper to combine parent and child indices
                                    subIndex = parent: i:
                                        if parent == "" then "${toString i}" else "${parent}.${toString i}";
                                in
                                    if elem == null then
                                        # Skip nulls, increment errorIndex
                                        advance (run // { errorIndex = idx; }) (lib.add (builtins.fromJSON "1") idx) # no-op if idx numeric, adjust later
                                    else if lib.isList elem then
                                        # Process list elements, subindices like "2.0", "2.1"
                                        let
                                            listElems = (lib.imap1
                                                (i: subElem:
                                                    { subElem = subElem; subIndex = subIndex idx (i - 1); })
                                                elem
                                            );
                                            result = (lib.foldl'
                                                (acc2: se:
                                                    let
                                                        r = process acc2.runningVals se.subIndex [ se.subElem ];
                                                    in
                                                        { runningVals = r.runningVals; currentErrorIndex = acc2.currentErrorIndex; })
                                                { runningVals = run; currentErrorIndex = idx; }
                                                listElems
                                            );
                                        in
                                            # After list, increment parent errorIndex (as if we processed one element)
                                            advance result.runningVals (toString (lib.toInt idx + 1))
                                    else if lib.isFunction elem then
                                        let
                                            result = elem run;
                                        in
                                            if lib.isFunction result then
                                                err "Function returned another function — invalid"
                                            else
                                                process run idx [ result ]
                                    else if lib.isAttrs elem then
                                        let
                                            onlyIf =
                                                if elem ? onlyIf then elem.onlyIf else true;
                                        in
                                            if onlyIf == true then
                                                let
                                                    newAll = run.prevAttrsets ++ [ elem ];
                                                    newMergedVals = lib.recursiveUpdate run.mergedVals elem.vals;
                                                    mapOverFlagged = (flags: mapCallback:
                                                        let
                                                            hasAllFlags = (eachElement:
                                                                eachElement ? flags && (builtins.typeOf eachElement.flags) == "set" && (lib.all
                                                                    (eachFlagString: eachElement.flags ? "${eachFlagString}")
                                                                    flags
                                                                )
                                                            );
                                                        in
                                                            if builtins.length flags == 0 then
                                                                lib.map mapCallback newAll
                                                            else
                                                                lib.map mapCallback (lib.filter hasAllFlags newAll)
                                                    );
                                                    newRunningVals = run // {
                                                        prevVals = (builtins.map
                                                            (each: each.vals)
                                                            newAll
                                                        );
                                                        prevAttrsets = newAll;
                                                        mergedVals = newMergedVals;
                                                        errorIndex = idx;
                                                        getAll = ({ hasAllFlags?[], filterIn?(each: true), attrPath?null, mapVals?(eachVals: eachVals), keepNullVals?false, strAppend?null, mergeVals?false, strJoin?null, }: 
                                                            let
                                                                elementsAfterHasAllFlags = mapOverFlagged hasAllFlags (each: each);
                                                                elementsAfterCustomFilter = (builtins.filter
                                                                    filterIn
                                                                    elementsAfterHasAllFlags
                                                                );
                                                                filteredValsAfterAttrPath = (
                                                                    if attrPath == null then
                                                                        elementsAfterCustomFilter
                                                                    else
                                                                        (builtins.map
                                                                            (each:
                                                                                if hasDeepAttribute each ([ "vals" ] ++ attrPath) then
                                                                                    getDeepAttribute each ([ "vals" ] ++ attrPath)
                                                                                else
                                                                                    null
                                                                            )
                                                                            elementsAfterCustomFilter
                                                                        )
                                                                );
                                                                filteredValsAfterAttrPathAndMap = (builtins.map
                                                                    mapVals
                                                                    filteredValsAfterAttrPath
                                                                );
                                                                filteredAndMapped = (
                                                                    if !(builtins.isString strAppend) then
                                                                        filteredValsAfterAttrPathAndMap
                                                                    else
                                                                        (builtins.map
                                                                            (each:
                                                                                if canBeNicelyCorcedToString each then
                                                                                    (builtins.toString each) + strAppend
                                                                                else
                                                                                    each
                                                                            )
                                                                            filteredValsAfterAttrPathAndMap
                                                                        )
                                                                );
                                                                filteredAndMappedNoNulls = (builtins.filter
                                                                    (each: keepNullVals || each != null)
                                                                    filteredAndMapped
                                                                );
                                                                filteredMappedMaybeMergedVals = (
                                                                    if mergeVals != false && mergeVals != null then
                                                                        (builtins.foldl'
                                                                            (acc: elem:
                                                                                # skip nulls
                                                                                if elem == null then
                                                                                    acc
                                                                                # else if not attrs, elem wins. Itd probably be good to have a warning here but oh well
                                                                                else if !(builtins.isAttrs acc) || !(builtins.isAttrs elem) then
                                                                                    elem
                                                                                else
                                                                                    lib.recursiveUpdate acc elem
                                                                            )
                                                                            {}
                                                                            filteredAndMappedNoNulls
                                                                        )
                                                                    else if (builtins.typeOf strJoin) == "string" then
                                                                        (builtins.foldl'
                                                                            (acc: elem:
                                                                                # skip nulls
                                                                                if elem == null then
                                                                                    if acc == null then
                                                                                        ""
                                                                                    else
                                                                                        acc
                                                                                # concat if strings
                                                                                else if canBeNicelyCorcedToString elem then
                                                                                    if acc == null then
                                                                                        (builtins.toString elem)
                                                                                    else
                                                                                        acc + strJoin + (builtins.toString elem)
                                                                                else
                                                                                    (builtins.trace
                                                                                        (builtins.trace
                                                                                            "got problematic value:"
                                                                                            elem
                                                                                        )
                                                                                        throw "aggregator: strJoin only works with strings and things that nicely coerce to strings (paths, ints, etc), instead of any of those I got a type of ${builtins.typeOf elem}"
                                                                                    )
                                                                            )
                                                                            null
                                                                            filteredAndMappedNoNulls
                                                                        )
                                                                    else
                                                                        filteredAndMappedNoNulls
                                                                );
                                                            in
                                                                filteredMappedMaybeMergedVals
                                                        );
                                                        # mapOverFlagged = mapOverFlagged;
                                                        # mergeFlagged = { attrPath, flags?[], ... }: (builtins.foldl'
                                                        #     (acc: elem:
                                                        #         if (hasDeepAttribute attrPath elem) then
                                                        #             lib.recursiveUpdate acc (getDeepAttribute elem attrPath)
                                                        #         else
                                                        #             acc
                                                        #     )
                                                        #     {}
                                                        #     (mapOverFlagged flags (each: each.vals))
                                                        # );
                                                    };
                                                in
                                                    advance newRunningVals (toString (lib.toInt idx + 1))
                                            else if onlyIf == false then
                                                advance (run // { errorIndex = idx; }) (toString (lib.toInt idx + 1))
                                            else
                                                err "the 'onlyIf' attr must be true or false, but got type ${lib.typeOf onlyIf} (in nix values like 1 are not 'truthy')"
                                    else
                                        err "aggregator only supports attrsets, lists, and functions, but got an element of type: ${lib.typeOf elem}"
                            )
                            { runningVals = runningVals; currentErrorIndex = parentIndex; }
                            elems
                    );

                    initial = {
                        prevVals = [];
                        prevAttrsets = [];
                        mergedVals = {};
                        getAll = ({ hasAllFlags?[], filterIn?(each: true), attrPath?null, mapVals?(eachVals: eachVals), strAppend?null, mergeVals?false, strJoin?null, }:
                            if mergeVals != false && mergeVals != null then
                                {}
                            else if builtins.isString strJoin then
                                ""
                            else
                                []
                        );
                        errorIndex = "0";
                    };

                    result = process initial "0" list;
                in
                    result.runningVals
            );
        in
            lib // flakeUtils.lib // {
                builtins = builtins;
                print = print;
                isUrl = isUrl;
                readJson = readJson;
                readToml = readToml;
                hasDeepAttribute = hasDeepAttribute;
                getDeepAttribute = getDeepAttribute;
                getDeepAttributeSafely = getDeepAttributeSafely;
                aggregator = aggregator;
            }
    ;
}