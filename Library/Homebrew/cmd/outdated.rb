#:  * `outdated` [`--quiet`|`--verbose`|`--json=`<version>] [`--fetch-HEAD`]:
#:    Show formulae that have an updated version available.
#:
#:    By default, version information is displayed in interactive shells, and
#:    suppressed otherwise.
#:
#:    If `--quiet` is passed, list only the names of outdated brews (takes
#:    precedence over `--verbose`).
#:
#:    If `--verbose` (or `-v`) is passed, display detailed version information.
#:
#:    If `--json=`<version> is passed, the output will be in JSON format.
#:    Currently the only accepted value for <version> is `v1`.
#:
#:    If `--fetch-HEAD` is passed, fetch the upstream repository to detect if
#:    the HEAD installation of the formula is outdated. Otherwise, the
#:    repository's HEAD will be checked for updates when a new stable or devel
#:    version has been released.

require "formula"
require "keg"
require "cli_parser"

module Homebrew
  module_function

  def outdated_args
    Homebrew::CLI::Parser.new do
      usage_banner <<~EOS
        `outdated` [<options>]

        Show formulae that have an updated version available.

        By default, version information is displayed in interactive shells, and
        suppressed otherwise.
      EOS
      switch :quiet,
        description: "List only the names of outdated brews (takes precedence over `--verbose`)."
      switch :verbose,
        description: "Display detailed version information."
      flag "--json=",
        description: "Show output in JSON format for provided <version>. Currently the only "\
                     "accepted value of <version> is `v1`."
      switch "--fetch-HEAD",
        description: "Fetch the upstream repository to detect if the HEAD installation of the "\
                     "formula is outdated. Otherwise, the repository's HEAD will be checked for "\
                     "updates when a new stable or devel version has been released."
      switch :debug
    end
  end

  def outdated
    outdated_args.parse

    formulae = if ARGV.resolved_formulae.empty?
      Formula.installed
    else
      ARGV.resolved_formulae
    end
    puts "\n[Library/Homebrew/cmd/outdated.rb => outdated DEBUG] formulae = #{formulae}\n\n"


    if args.json == "v1"
      outdated = print_outdated_json(formulae)
    else
      outdated = print_outdated(formulae)
    end
    Homebrew.failed = !ARGV.resolved_formulae.empty? && !outdated.empty?
  end

  def print_outdated(formulae)
    verbose = ($stdout.tty? || args.verbose?) && !args.quiet?
    fetch_head = args.fetch_HEAD?

    outdated_formulae = formulae.select { |f| f.outdated?(fetch_head: fetch_head) }
                                .sort

    outdated_formulae.each do |f|
      if verbose
        outdated_kegs = f.outdated_kegs(fetch_head: fetch_head)

        current_version = if f.alias_changed?
          latest = f.latest_formula
          "#{latest.name} (#{latest.pkg_version})"
        elsif f.head? && outdated_kegs.any? { |k| k.version.to_s == f.pkg_version.to_s }
          # There is a newer HEAD but the version number has not changed.
          "latest HEAD"
        else
          f.pkg_version.to_s
        end

        outdated_versions = outdated_kegs
                            .group_by { |keg| Formulary.from_keg(keg).full_name }
                            .sort_by { |full_name, _kegs| full_name }
                            .map do |full_name, kegs|
          "#{full_name} (#{kegs.map(&:version).join(", ")})"
        end.join(", ")

        pinned_version = " [pinned at #{f.pinned_version}]" if f.pinned?

        puts "#{outdated_versions} < #{current_version}#{pinned_version}"
      else
        puts f.full_installed_specified_name
      end
    end
  end

  def print_outdated_json(formulae)
    json = []
    fetch_head = args.fetch_HEAD?
    outdated_formulae = formulae.select { |f| f.outdated?(fetch_head: fetch_head) }

    outdated = outdated_formulae.each do |f|
      outdated_versions = f.outdated_kegs(fetch_head: fetch_head).map(&:version)
      current_version = if f.head? && outdated_versions.any? { |v| v.to_s == f.pkg_version.to_s }
        "HEAD"
      else
        f.pkg_version.to_s
      end

      json << { name:               f.full_name,
                installed_versions: outdated_versions.map(&:to_s),
                current_version:    current_version,
                pinned:             f.pinned?,
                pinned_version:     f.pinned_version }
    end
    puts JSON.generate(json)

    outdated
  end
end
