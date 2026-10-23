// Command line front-ends: omnom-install, omnom-remove, omnom-upgrade,
// omnom-rollback. All four are subcommands of the omnom-pkg binary.

#include "common.hpp"

#include <unistd.h>

#include <algorithm>
#include <iostream>
#include <set>
#include <sstream>

namespace omnom {
namespace {

void print_generation_state(const State &state) {
    const auto current = state.current_generation();
    if (current) {
        std::cout << "[omnom] generation " << *current << " is now active\n";
    }
    std::cout << "[omnom] " << state.packages().size() << " package(s) recorded\n";
}

string first_token(const string &line) {
    const auto space = line.find(' ');
    return space == string::npos ? line : line.substr(0, space);
}

string join(const vector<string> &parts, const string &separator) {
    string result;
    for (const auto &part : parts) {
        if (!result.empty()) {
            result += separator;
        }
        result += part;
    }
    return result;
}

string join_methods(const std::set<string> &methods) {
    string result;
    for (const auto &method : methods) {
        if (!result.empty()) {
            result += '+';
        }
        result += method;
    }
    return result.empty() ? "none" : result;
}

bool confirm(const string &question, bool assume_yes) {
    if (assume_yes) {
        return true;
    }
    if (!isatty(STDIN_FILENO)) {
        std::cerr << "[omnom] refusing to continue without --yes in a non-interactive session\n";
        return false;
    }
    std::cout << question << " [y/N] " << std::flush;
    string answer;
    if (!std::getline(std::cin, answer)) {
        return false;
    }
    return answer == "y" || answer == "Y" || answer == "yes" || answer == "YES";
}

optional<fs::path> prescan_config(const vector<string> &args) {
    for (size_t index = 0; index < args.size(); ++index) {
        if (args[index] == "--config") {
            if (index + 1 >= args.size()) {
                usage_error("--config requires a value");
            }
            return fs::path(args[index + 1]);
        }
    }
    return std::nullopt;
}

string value_of(const vector<string> &args, size_t &index, const string &option) {
    if (index + 1 >= args.size()) {
        usage_error(option + " requires a value");
    }
    ++index;
    return args[index];
}

optional<Method> effective_method(const Config &config, const optional<Method> &cli_method) {
    if (cli_method) {
        return cli_method;
    }
    if (config.default_method == "auto") {
        return std::nullopt;
    }
    return parse_method(config.default_method);
}

void print_package_list(const State &state) {
    const auto packages = state.packages();
    const auto current = state.current_generation();
    std::cout << "[omnom] packages managed by Omnom ("
              << (current ? *current : "no generation") << "): " << packages.size() << '\n';
    for (const auto &entry : packages) {
        const string method = state.managed_get(first_token(entry));
        std::cout << "  " << entry;
        if (!method.empty()) {
            std::cout << "  [" << method << "]";
        }
        std::cout << '\n';
    }
    if (packages.empty()) {
        std::cout << "  (none yet; use --list-all to see backend packages)\n";
    }
}

int search_all(const Config &config, Runner &runner, const string &term,
               const optional<Method> &forced) {
    const auto order = backend_order(config, runner, forced);
    if (order.empty()) {
        std::cerr << "[omnom] no supported package backend is available\n";
        return 1;
    }
    vector<string> rows;
    for (const auto method : order) {
        try {
            const auto found = backend_search(method, term, config, runner);
            rows.insert(rows.end(), found.begin(), found.end());
        } catch (const Error &error) {
            std::cerr << "[omnom] warning: " << to_string(method) << ": " << error.what() << '\n';
        }
    }
    if (rows.empty()) {
        std::cout << "[omnom] no packages matching '" << term << "'\n";
        return 0;
    }
    std::cout << "[omnom] " << rows.size() << " match(es) for '" << term << "'\n";
    for (const auto &row : rows) {
        std::cout << row << '\n';
    }
    return 0;
}

}  // namespace

void usage_error(const string &message) {
    std::cerr << "[omnom] " << message << '\n';
    std::exit(2);
}

void print_help(const string &program, const string &usage, const vector<string> &examples) {
    std::cout << "Usage: " << usage << "\n\n" << program << "\n";
    if (!examples.empty()) {
        std::cout << "\nExamples:\n";
        for (const auto &example : examples) {
            std::cout << "  " << example << '\n';
        }
    }
    std::cout << "\nCommon options:\n"
                 "  --config FILE   configuration file (default: /etc/omnom/omnom.conf)\n"
                 "  --dry-run       print what would happen, change nothing\n"
                 "  -y, --yes       do not ask for confirmation\n";
}

// ---------------------------------------------------------------------------
// omnom-install
// ---------------------------------------------------------------------------
int cmd_install(const vector<string> &args) {
    enum class Mode { Install, List, ListAll, Search };
    Mode mode = Mode::Install;
    string search_term;
    optional<Method> cli_method;
    bool dry_run = false;
    bool yes = false;
    bool no_generation = false;
    vector<string> packages;

    const auto config_path = prescan_config(args);

    for (size_t index = 0; index < args.size(); ++index) {
        const string &argument = args[index];
        if (argument == "--help" || argument == "-h") {
            print_help("Install packages or inspect the system.",
                       "omnom-install [options] [package...]",
                       {"omnom-install firefox", "omnom-install firefox --pacman",
                        "omnom-install htop --our --dry-run", "omnom-install --list",
                        "omnom-install --search browser"});
            return 0;
        } else if (argument == "--list") {
            mode = Mode::List;
        } else if (argument == "--list-all") {
            mode = Mode::ListAll;
        } else if (argument == "--search") {
            mode = Mode::Search;
            search_term = value_of(args, index, "--search");
        } else if (argument == "--dnf" || argument == "--pacman" || argument == "--apt" ||
                   argument == "--aur" || argument == "--our" || argument == "--emerge") {
            cli_method = parse_method(argument.substr(2));
        } else if (argument == "--dry-run") {
            dry_run = true;
        } else if (argument == "-y" || argument == "--yes") {
            yes = true;
        } else if (argument == "--no-generation") {
            no_generation = true;
        } else if (argument == "--config") {
            ++index;  // already handled by prescan_config
        } else if (!argument.empty() && argument[0] == '-') {
            usage_error("unknown option '" + argument + "'");
        } else {
            packages.push_back(argument);
        }
    }

    Config config = load_config(config_path);
    config.dry_run = config.dry_run || dry_run;
    Runner runner(config.dry_run);
    State state(config);
    const auto forced = effective_method(config, cli_method);

    if (mode == Mode::List) {
        print_package_list(state);
        return 0;
    }
    if (mode == Mode::Search) {
        if (search_term.empty()) {
            usage_error("--search needs a non-empty term");
        }
        return search_all(config, runner, search_term, forced);
    }
    if (mode == Mode::ListAll) {
        const auto order = backend_order(config, runner, forced);
        if (order.empty()) {
            std::cerr << "[omnom] no supported package backend is available\n";
            return 1;
        }
        for (const auto method : order) {
            const auto entries = backend_list(method, config, runner);
            std::cout << "[omnom] " << label(method) << ": " << entries.size()
                      << " package(s)\n";
            for (const auto &entry : entries) {
                std::cout << "  " << entry << '\n';
            }
        }
        return 0;
    }

    if (packages.empty()) {
        print_help("Install packages or inspect the system.",
                   "omnom-install [options] [package...]",
                   {"omnom-install firefox", "omnom-install --list"});
        return 2;
    }

    vector<std::pair<string, vector<Method>>> plan;
    for (const auto &package : packages) {
        auto candidates = candidates_for(package, config, runner, forced);
        plan.emplace_back(package, std::move(candidates));
        std::cout << (config.dry_run ? "[dry-run] " : "[omnom] ") << package << " -> "
                  << label(plan.back().second.front()) << '\n';
    }

    if (config.dry_run) {
        std::cout << "[dry-run] no changes made\n";
        return 0;
    }
    if (!confirm("Install " + join(packages, ", ") + "?", yes)) {
        std::cout << "[omnom] cancelled\n";
        return 1;
    }

    std::set<string> methods;
    vector<string> installed;
    for (const auto &[package, candidates] : plan) {
        const Method method = install_with_fallback(package, candidates, config, runner);
        state.managed_set(package, to_string(method));
        state.add_packages({package});
        methods.insert(to_string(method));
        installed.push_back(package);
    }

    if (!no_generation) {
        state.create_generation("install " + join(installed, " "), join_methods(methods));
        print_generation_state(state);
    }
    state.history("installed " + join(installed, " ") + " via " + join_methods(methods));
    std::cout << "[omnom] installed: " << join(installed, ", ") << '\n';
    return 0;
}

// ---------------------------------------------------------------------------
// omnom-remove
// ---------------------------------------------------------------------------
int cmd_remove(const vector<string> &args) {
    optional<Method> cli_method;
    bool dry_run = false;
    bool yes = false;
    vector<string> packages;
    const auto config_path = prescan_config(args);

    for (size_t index = 0; index < args.size(); ++index) {
        const string &argument = args[index];
        if (argument == "--help" || argument == "-h") {
            print_help("Remove packages installed through Omnom.",
                       "omnom-remove [options] package...",
                       {"omnom-remove firefox", "omnom-remove htop --yes"});
            return 0;
        } else if (argument == "--dnf" || argument == "--pacman" || argument == "--apt" ||
                   argument == "--aur" || argument == "--our" || argument == "--emerge") {
            cli_method = parse_method(argument.substr(2));
        } else if (argument == "--dry-run") {
            dry_run = true;
        } else if (argument == "-y" || argument == "--yes") {
            yes = true;
        } else if (argument == "--config") {
            ++index;
        } else if (!argument.empty() && argument[0] == '-') {
            usage_error("unknown option '" + argument + "'");
        } else {
            packages.push_back(argument);
        }
    }

    if (packages.empty()) {
        usage_error("no package names given");
    }

    Config config = load_config(config_path);
    config.dry_run = config.dry_run || dry_run;
    Runner runner(config.dry_run);
    State state(config);
    const auto forced = effective_method(config, cli_method);
    const auto order = backend_order(config, runner, forced);
    if (order.empty()) {
        std::cerr << "[omnom] no supported package backend is available\n";
        return 1;
    }

    vector<std::pair<string, Method>> plan;
    for (const auto &package : packages) {
        optional<Method> recorded = parse_method(state.managed_get(package));
        Method method = recorded ? *recorded : order.front();
        if (!backend_available(method, config, runner)) {
            throw Error("backend '" + to_string(method) + "' needed for " + package +
                        " is not available");
        }
        plan.emplace_back(package, method);
    }

    if (config.dry_run) {
        for (const auto &[package, method] : plan) {
            std::cout << "[dry-run] remove " << package << " with " << label(method) << '\n';
        }
        return 0;
    }
    if (!confirm("Remove " + join(packages, ", ") + "?", yes)) {
        std::cout << "[omnom] cancelled\n";
        return 1;
    }

    std::set<string> methods;
    for (const auto &[package, method] : plan) {
        backend_remove(method, package, config, runner);
        state.managed_del(package);
        state.drop_packages({package});
        methods.insert(to_string(method));
    }
    state.create_generation("remove " + join(packages, " "), join_methods(methods));
    print_generation_state(state);
    std::cout << "[omnom] removed: " << join(packages, ", ") << '\n';
    return 0;
}

// ---------------------------------------------------------------------------
// omnom-upgrade
// ---------------------------------------------------------------------------
int cmd_upgrade(const vector<string> &args) {
    optional<Method> cli_method;
    optional<string> target;
    optional<string> switch_to;
    bool all = false;
    bool check = false;
    bool rollback = false;
    bool list_generations = false;
    bool dry_run = false;
    bool yes = false;
    const auto config_path = prescan_config(args);

    for (size_t index = 0; index < args.size(); ++index) {
        const string &argument = args[index];
        if (argument == "--help" || argument == "-h") {
            print_help("Update packages, inspect updates and manage generations.",
                       "omnom-upgrade [options] [package|our]",
                       {"omnom-upgrade --all", "omnom-upgrade firefox",
                        "omnom-upgrade --check", "omnom-upgrade --rollback",
                        "omnom-upgrade --list-generations", "omnom-upgrade --switch gen-..."});
            return 0;
        } else if (argument == "--all") {
            all = true;
        } else if (argument == "--check") {
            check = true;
        } else if (argument == "--rollback") {
            rollback = true;
        } else if (argument == "--list-generations") {
            list_generations = true;
        } else if (argument == "--switch") {
            switch_to = value_of(args, index, "--switch");
        } else if (argument == "--dnf" || argument == "--pacman" || argument == "--apt" ||
                   argument == "--aur" || argument == "--our" || argument == "--emerge") {
            cli_method = parse_method(argument.substr(2));
        } else if (argument == "--dry-run") {
            dry_run = true;
        } else if (argument == "-y" || argument == "--yes") {
            yes = true;
        } else if (argument == "--config") {
            ++index;
        } else if (!argument.empty() && argument[0] == '-') {
            usage_error("unknown option '" + argument + "'");
        } else if (!target) {
            target = argument;
        } else {
            usage_error("only one package can be upgraded at a time");
        }
    }

    Config config = load_config(config_path);
    config.dry_run = config.dry_run || dry_run;
    Runner runner(config.dry_run);
    State state(config);
    const auto forced = effective_method(config, cli_method);

    if (list_generations) {
        state.print_generations();
        return 0;
    }
    if (switch_to) {
        state.switch_generation(*switch_to);
        print_generation_state(state);
        return 0;
    }
    if (rollback) {
        const auto previous = state.previous_generation();
        if (!previous) {
            std::cerr << "[omnom] no previous generation to roll back to\n";
            return 1;
        }
        state.switch_generation(*previous);
        print_generation_state(state);
        return 0;
    }
    if (check) {
        const auto order = backend_order(config, runner, forced);
        if (order.empty()) {
            std::cerr << "[omnom] no supported package backend is available\n";
            return 1;
        }
        size_t total = 0;
        for (const auto method : order) {
            const auto updates = backend_check(method, config, runner);
            total += updates.size();
            std::cout << "[omnom] " << label(method) << ": " << updates.size()
                      << " update(s)\n";
            for (const auto &line : updates) {
                std::cout << "  " << line << '\n';
            }
        }
        if (total == 0) {
            std::cout << "[omnom] everything is up to date\n";
        }
        return 0;
    }
    if (!all && !target) {
        usage_error("choose --all, a package, 'our', --check, --rollback or --list-generations");
    }

    if (config.dry_run) {
        std::cout << "[dry-run] update " << (target ? *target : "the whole system") << '\n';
        return 0;
    }
    if (!confirm("Update " + (target ? *target : string("the whole system")) + "?", yes)) {
        std::cout << "[omnom] cancelled\n";
        return 1;
    }

    std::set<string> methods;
    if (all) {
        const auto order = backend_order(config, runner, forced);
        if (order.empty()) {
            std::cerr << "[omnom] no supported package backend is available\n";
            return 1;
        }
        backend_upgrade(order.front(), std::nullopt, config, runner);
        methods.insert(to_string(order.front()));
        if (std::find(order.begin(), order.end(), Method::Our) != order.end() &&
            order.front() != Method::Our) {
            our_upgrade(config, runner, std::nullopt);
            methods.insert("our");
        }
    } else if (*target == "our") {
        our_upgrade(config, runner, std::nullopt);
        methods.insert("our");
    } else {
        Method method;
        if (const auto recorded = parse_method(state.managed_get(*target))) {
            method = *recorded;
        } else {
            const auto candidates = candidates_for(*target, config, runner, forced);
            if (candidates.empty()) {
                throw Error("no backend can upgrade " + *target);
            }
            method = candidates.front();
        }
        backend_upgrade(method, target, config, runner);
        methods.insert(to_string(method));
    }

    state.create_generation("upgrade " + (target ? *target : string("all")),
                            join_methods(methods));
    print_generation_state(state);
    return 0;
}

// ---------------------------------------------------------------------------
// omnom-rollback
// ---------------------------------------------------------------------------
int cmd_rollback(const vector<string> &args) {
    optional<string> generation;
    bool list = false;
    bool dry_run = false;
    const auto config_path = prescan_config(args);

    for (size_t index = 0; index < args.size(); ++index) {
        const string &argument = args[index];
        if (argument == "--help" || argument == "-h") {
            print_help("Switch the active generation.",
                       "omnom-rollback [options] [generation]",
                       {"omnom-rollback", "omnom-rollback gen-20261023_083000",
                        "omnom-rollback --list"});
            return 0;
        } else if (argument == "--list") {
            list = true;
        } else if (argument == "--dry-run") {
            dry_run = true;
        } else if (argument == "-y" || argument == "--yes") {
            // rollback itself needs no confirmation
        } else if (argument == "--config") {
            ++index;
        } else if (!argument.empty() && argument[0] == '-') {
            usage_error("unknown option '" + argument + "'");
        } else if (!generation) {
            generation = argument;
        } else {
            usage_error("only one generation can be given");
        }
    }

    Config config = load_config(config_path);
    config.dry_run = config.dry_run || dry_run;
    State state(config);

    if (list) {
        state.print_generations();
        return 0;
    }

    optional<string> target = generation;
    if (!target) {
        target = state.previous_generation();
        if (!target) {
            std::cerr << "[omnom] no previous generation to roll back to\n";
            return 1;
        }
    }

    if (config.dry_run) {
        std::cout << "[dry-run] switch to " << *target << '\n';
        return 0;
    }
    state.switch_generation(*target);
    print_generation_state(state);
    return 0;
}

}  // namespace omnom
