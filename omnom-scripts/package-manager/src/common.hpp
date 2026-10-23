// Omnom package manager - shared declarations.
//
// Copyright (C) 2026 Omnom Linux contributors. GPL-3.0-or-later.
//
// The package manager is C++17 with no external dependencies so it can be
// built by the same GCC that a fresh LFS/Omnom system already provides.

#pragma once

#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace omnom {

namespace fs = std::filesystem;
using std::optional;
using std::string;
using std::vector;

struct Error : std::runtime_error {
    explicit Error(const string &message) : std::runtime_error(message) {}
};

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
struct Config {
    fs::path state_dir{"/var/lib/omnom"};
    fs::path profile_root{"/omnom/profiles"};
    fs::path our_repo;
    fs::path cache_dir;
    fs::path install_root{"/"};
    string default_method{"auto"};
    int generations_keep{10};
    string cflags{"-O2 -march=native -pipe"};
    string makeopts;
    bool our_repo_enabled{true};
    bool dry_run{false};
};

// Loads /etc/omnom/omnom.conf (or $OMNOM_CONFIG) and applies OMNOM_*
// environment overrides. Throws Error on invalid values.
Config load_config(const optional<fs::path> &path);

// ---------------------------------------------------------------------------
// Process execution
// ---------------------------------------------------------------------------
struct RunResult {
    int status{0};
    string output;
    bool ok() const { return status == 0; }
};

class Runner {
public:
    explicit Runner(bool dry_run) : dry_run_(dry_run) {}

    bool dry_run() const { return dry_run_; }
    bool which(const string &program) const;

    // Runs argv, printing the command unless capture is true. mutate prefixes
    // sudo when not running as root. When capture is true stdout is collected
    // and stderr is discarded.
    RunResult run(const vector<string> &argv, bool mutate = true, bool capture = false);

    // Runs a shell snippet inside cwd with extra environment variables.
    RunResult shell(const string &script, const fs::path &cwd,
                    const vector<std::pair<string, string>> &env, bool mutate = true);

private:
    bool dry_run_;
};

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
class State {
public:
    explicit State(const Config &config);

    void ensure() const;
    void history(const string &message) const;

    vector<string> packages() const;
    void add_packages(const vector<string> &names) const;
    void drop_packages(const vector<string> &names) const;
    bool tracked(const string &package) const;

    string managed_get(const string &package) const;
    void managed_set(const string &package, const string &method) const;
    void managed_del(const string &package) const;

    vector<string> generation_names() const;  // newest first
    bool generation_exists(const string &name) const;
    optional<string> current_generation() const;
    string generation_meta(const string &name, const string &key) const;
    string create_generation(const string &reason, const string &method) const;
    void switch_generation(const string &name) const;
    optional<string> previous_generation() const;
    void prune() const;
    void print_generations() const;

    const Config &config() const { return config_; }

private:
    void profile_sync(const fs::path &generation_path) const;
    fs::path generations_dir() const { return config_.state_dir / "generations"; }
    fs::path packages_file() const { return config_.state_dir / "packages.list"; }
    fs::path managed_file() const { return config_.state_dir / "managed.list"; }
    Config config_;
};

// ---------------------------------------------------------------------------
// OUR packages
// ---------------------------------------------------------------------------
struct Pkg {
    string name;
    string version;
    string description;
    string source;
    string sha256;
    string build;
    string install;
    string depends;
    string homepage;
    fs::path path;
};

Pkg parse_pkg(const fs::path &path);           // throws Error when invalid
vector<Pkg> scan_repo(const fs::path &repo);
optional<Pkg> find_pkg(const fs::path &repo, const string &name);

void our_install(const Config &config, Runner &runner, const string &name);
void our_remove(const Config &config, Runner &runner, const string &name);
void our_upgrade(const Config &config, Runner &runner, const optional<string> &name);
vector<string> our_updates(const Config &config);
vector<string> our_installed(const Config &config);  // "name version"
vector<Pkg> search_our(const Config &config, const string &term);

// ---------------------------------------------------------------------------
// Backends
// ---------------------------------------------------------------------------
enum class Method { Dnf, Pacman, Apt, Aur, Our, Emerge };

string to_string(Method method);
optional<Method> parse_method(const string &name);
string label(Method method);
int priority(Method method);

bool backend_available(Method method, const Config &config, Runner &runner);
bool backend_has(Method method, const string &package, const Config &config, Runner &runner);
void backend_install(Method method, const string &package, const Config &config, Runner &runner);
void backend_remove(Method method, const string &package, const Config &config, Runner &runner);
void backend_upgrade(Method method, const optional<string> &package, const Config &config,
                     Runner &runner);
vector<string> backend_check(Method method, const Config &config, Runner &runner);
vector<string> backend_list(Method method, const Config &config, Runner &runner);
vector<string> backend_search(Method method, const string &term, const Config &config,
                              Runner &runner, const string &prefix = "  ");

vector<Method> backend_order(const Config &config, Runner &runner, const optional<Method> &forced);
vector<Method> candidates_for(const string &package, const Config &config, Runner &runner,
                              const optional<Method> &forced);

// Installs one package, trying candidates in order. Returns the method that
// succeeded. Throws Error when every candidate fails.
Method install_with_fallback(const string &package, const vector<Method> &candidates,
                             const Config &config, Runner &runner);

// ---------------------------------------------------------------------------
// CLI entry points
// ---------------------------------------------------------------------------
int cmd_install(const vector<string> &args);
int cmd_remove(const vector<string> &args);
int cmd_upgrade(const vector<string> &args);
int cmd_rollback(const vector<string> &args);

// Shared helpers used by the commands.
void print_help(const string &program, const string &usage, const vector<string> &examples);
[[noreturn]] void usage_error(const string &message);

}  // namespace omnom
