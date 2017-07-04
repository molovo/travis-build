module Travis
  module Build
    class Script
      class ZSH < Script
        DEFAULT_VERSION = "5.3.1"

        DEPENDENCIES = {
          :zvm = "https://raw.githubusercontent.com/molovo/zvm/master/zvm",
          :revoler = "https://raw.githubusercontent.com/molovo/revolver/master/revolver",
          :color = "https://raw.githubusercontent.com/molovo/color/master/color.zsh",
          :zunit = "https://github.com/molovo/zunit/releases/download/v0.7.0/zunit"
        }

        def setup
          super
          prepend_path ".bin"
          sh.cmd "mkdir -p .bin"
          sh.cmd "curl -L #{DEPENDENCIES[:zvm]} > .bin/zvm"
        end

        def export
          super
          if zsh_given_in_config?
            sh.export "TRAVIS_ZSH_VERSION", version, echo: false
          end
        end

        def announce
          super
          sh.cmd "zsh --version"
          sh.cmd "zvm --version"

          sh.if "$([[ -f .zunit.yml || -d tests ]])" do
            sh.cmd "zunit --version"
          end
        end

        def install
          sh.if "$([[ -f .zunit.yml || -d tests ]])" do
            sh.cmd "curl -L #{DEPENDENCIES[:revolver]} > .bin/revolver"
            sh.cmd "curl -L #{DEPENDENCIES[:color]} > .bin/color"
            sh.cmd "curl -L #{DEPENDENCIES[:zunit]} > .bin/zunit"
          end
        end

        def script
          sh.if "-f .zunit.yml" do
            sh.cmd "zunit"
          end
          sh.else do
            sh.cmd "make test"
          end
        end

        def cache_slug
          super << "--zsh-" << version
        end

        def zvm_install
          if zsh_given_in_config?
            use_zvm_version
          else
            use_zvm_default
          end
        end

        def use_zvm_default
          sh.if "-f .zvmrc" do
            sh.echo "Using ZSH version from .zvmrc", ansi: :yellow
            install_version "$(< .zvmrc)"
          end
          sh.else do
            install_version DEFAULT_VERSION
          end
        end

        def use_zvm_version
          install_version version
        end

        def install_version(ver)
          sh.fold "zvm.install" do
            sh.cmd "zvm install #{ver}", assert: false, timing: true
            sh.if "$? -ne 0" do
              sh.echo "Failed to install #{ver}. Remote repository may not be reachable.", ansi: :red
              sh.echo "Using locally available version #{ver}, if applicable."
              sh.cmd "zvm use #{ver}", assert: false, timing: false
              sh.if "$? -ne 0" do
                sh.echo "Unable to use #{ver}", ansi: :red
                sh.cmd "false", assert: true, echo: false, timing: false
              end
            end
            sh.export "TRAVIS_ZSH_VERSION", ver, echo: false
          end
        end

        def prepend_path(path)
          sh.if "$(echo :$PATH: | grep -v :#{path}:)" do
            sh.export "PATH", "#{path}:$PATH", echo: true
          end
        end
      end
    end
  end
end
