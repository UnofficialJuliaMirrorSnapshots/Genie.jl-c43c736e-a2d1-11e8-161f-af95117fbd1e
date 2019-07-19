module REPL

using Revise, SHA, Dates, Pkg
using Genie, Genie.Loggers, Genie.Configuration, Genie.Generator, Genie.Tester, Genie.Util, Genie.FileTemplates

const JULIA_PATH = joinpath(Sys.BINDIR, "julia")


"""
    secret_token() :: String

Generates a random secret token to be used for configuring the SECRET_TOKEN const.
"""
function secret_token() :: String
  sha256("$(randn()) $(Dates.now())") |> bytes2hex
end


"""
    newapp(path::String; autostart = true, fullstack = false, dbsupport = false) :: Nothing

Creates a new Genie app at the indicated path.
"""
function newapp(path::String; autostart = true, fullstack = false, dbsupport = false) :: Nothing
  app_path = abspath(path)

  if fullstack
    cp(joinpath(@__DIR__, "../", "files", "new_app"), app_path)
  else
    mkdir(app_path)
    for f in ["app", "bin", "config", "lib", "log", "plugins", "public", "src",
              ".gitattributes", ".gitignore", "bootstrap.jl", "env.jl", "genie.jl"]
      cp(joinpath(@__DIR__, "../", "files", "new_app", f), joinpath(app_path, f))
    end
    rm(joinpath(app_path, "config", "initializers", "fingerprint.jl"), force = true)
  end

  if dbsupport
    fullstack || cp(joinpath(@__DIR__, "../", "files", "new_app", "db"), joinpath(app_path, "db"))
  else
    rm(joinpath(app_path, "config", "database.yml"), force = true)
    rm(joinpath(app_path, "config", "initializers", "searchlight.jl"), force = true)
  end

  # chmod(app_path, 0o644, recursive = true)

  chmod(joinpath(app_path, "bin", "server"), 0o700)
  chmod(joinpath(app_path, "bin", "repl"), 0o700)

  open(joinpath(app_path, "config", "secrets.jl"), "w") do f
    write(f, """const SECRET_TOKEN = "$(secret_token())" """)
  end

  moduleinfo = FileTemplates.appmodule(path)
  open(joinpath(app_path, "src", moduleinfo[1] * ".jl"), "w") do f
    write(f, moduleinfo[2])
  end

  chmod(joinpath(app_path, "bootstrap.jl"), 0o644)
  open(joinpath(app_path, "bootstrap.jl"), "w") do f
    write(f,
    """
      cd(@__DIR__)
      using Pkg
      pkg"activate ."

      function main()
        include(joinpath("src", "$(moduleinfo[1]).jl"))
      end

      main()
    """)
  end

  log("Done! New app created at $(abspath(path))", :info)

  Sys.iswindows() && setup_windows_bin_files(app_path)

  log("Changing active directory to $app_path")
  cd(path)

  log("Installing app dependencies")
  pkg"activate ."

  pkg"add Genie"
  pkg"add JSON"
  pkg"add Millboard"
  pkg"add Revise"

  if autostart
    log("Starting your brand new Genie app - hang tight!", :info)
    load_app(".", autostart = autostart)
  else
    log("Your new Genie app is ready!
        Run \njulia> Genie.loadapp() \nto load the app's environment
        and then \njulia> Genie.startup() \nto start the web server on port 8000.")
  end

  nothing
end
const new_app = newapp


"""
"""
function loadapp(path = "."; autostart = false) :: Nothing
  Core.eval(Main, Meta.parse("using Revise"))
  Core.eval(Main, Meta.parse("""include(joinpath("$path", "bootstrap.jl"))"""))
  Core.eval(Main, Meta.parse("Revise.revise()"))
  Core.eval(Main, Meta.parse("using Genie"))

  Core.eval(Main.UserApp, Meta.parse("Revise.revise()"))
  Core.eval(Main.UserApp, Meta.parse("$autostart && Genie.startup()"))

  nothing
end
const load_app = loadapp


"""

"""
function setup_windows_bin_files(path = ".")
  open(joinpath(path, "bin", "repl.bat"), "w") do f
    write(f, "$JULIA_PATH --color=yes --depwarn=no -q -i -- ../bootstrap.jl %*")
  end

  open(joinpath(path, "bin", "server.bat"), "w") do f
    write(f, "$JULIA_PATH --color=yes --depwarn=no -q -i -- ../bootstrap.jl s %*")
  end
end


"""
    write_secrets_file() :: Nothing

Generates a valid secrets.jl file with a random SECRET_TOKEN.
"""
function write_secrets_file() :: Nothing
  open(joinpath(Genie.CONFIG_PATH, "secrets.jl"), "w") do f
    write(f, """const SECRET_TOKEN = "$(secret_token())" """)
  end

  log("Generated secrets.jl file in $(Genie.CONFIG_PATH)", :info)

  nothing
end

end
