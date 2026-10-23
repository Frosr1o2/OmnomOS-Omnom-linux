// Native package manager backends: DNF, pacman, AUR, APT, Portage and OUR.

#include "common.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <set>
#include <sstream>

namespace omnom {
namespace {

struct MethodInfo {
    Method method;
    const char *name;
    const char *label;
    const char *probe;
    int priority;
};

const std::array<MethodInfo, 6> kMethods{{
    {Method::Dnf, "dnf", "DNF (RPM)", "dnf", 10},
    {Method::Pacman, "pacman", "pacman (Arch)", "pacman", 20},
    {Method::Apt, "apt", "APT (Debian)", "apt-get", 25},
    {Method::Aur, "aur", "AUR", "yay", 30},
    {Method::Our, "our", "OUR (Omnom User Repository)", "", 40},
    {Method::Emerge, "emerge", "Portage (source)", "emerge", 50},
}};

const MethodInfo &info(Method method) {
    for (const auto &entry : kMethods) {
        if (entry.method == method) {
            return entry;
        }
    }
    return kMethods.front();
}

vector<string> split_ws(const string &line) {
    std::istringstream stream(line);
    vector<string> parts;
    string part;
    while (stream >> part) {
        parts.push_back(part);
    }
    return parts;
}

string aur_helper(Runner &runner) {
    if (runner.which("yay")) {
        return "yay";
    }
    if (runner.which("paru")) {
        return "paru";
    }
    throw Error("no AUR helper (yay or paru) is installed");
}

void expect_ok(const RunResult &result, const string &what) {
    if (!result.ok()) {
        throw Error(what + " failed with status " + std::to_string(result.status));
    }
}

string format_row(const string &prefix, const string &method, const string &name,
                  const string &version, const string &description) {
    std::ostringstream out;
    out << prefix << std::left;
    out.width(7);
    out << method << ' ';
    out.width(24);
    out << name << ' ';
    out.width(16);
    out << version << ' ' << description;
    return out.str();
}

vector<string> non_empty_lines(const string &output) {
    vector<string> lines;
    std::istringstream stream(output);
    string line;
    while (std::getline(stream, line)) {
        if (!line.empty()) {
            lines.push_back(line);
        }
    }
    return lines;
}

}  // namespace

string to_string(Method method) { return info(method).name; }

optional<Method> parse_method(const string &name) {
    for (const auto &entry : kMethods) {
        if (name == entry.name) {
            return entry.method;
        }
    }
    return std::nullopt;
}

string label(Method method) { return info(method).label; }
int priority(Method method) { return info(method).priority; }

bool backend_available(Method method, const Config &config, Runner &runner) {
    switch (method) {
        case Method::Aur:
            return runner.which("yay") || runner.which("paru");
        case Method::Our:
            return config.our_repo_enabled && fs::is_directory(config.our_repo);
        default:
            return runner.which(info(method).probe);
    }
}

bool backend_has(Method method, const string &package, const Config &config, Runner &runner) {
    RunResult result;
    switch (method) {
        case Method::Dnf:
            return runner.run({"dnf", "-q", "info", package}, false, true).ok();
        case Method::Pacman:
            return runner.run({"pacman", "-Si", package}, false, true).ok();
        case Method::Apt:
            result = runner.run({"apt-cache", "show", package}, false, true);
            return result.ok() && result.output.find("Package:") != string::npos;
        case Method::Aur:
            return runner.run({aur_helper(runner), "-Si", package}, false, true).ok();
        case Method::Emerge:
            return runner.run({"emerge", "-p", package}, false, true).ok();
        case Method::Our:
            return find_pkg(config.our_repo, package).has_value();
    }
    return false;
}

void backend_install(Method method, const string &package, const Config &config, Runner &runner) {
    vector<string> argv;
    switch (method) {
        case Method::Dnf:
            argv = {"dnf", "install", "-y", package};
            break;
        case Method::Pacman:
            argv = {"pacman", "-S", "--needed", "--noconfirm", package};
            break;
        case Method::Apt:
            argv = {"apt-get", "install", "-y", package};
            break;
        case Method::Aur:
            argv = {aur_helper(runner), "-S", "--needed", "--noconfirm", package};
            break;
        case Method::Emerge:
            argv = {"emerge", package};
            break;
        case Method::Our:
            our_install(config, runner, package);
            return;
    }
    expect_ok(runner.run(argv), to_string(method) + " install " + package);
}

void backend_remove(Method method, const string &package, const Config &config, Runner &runner) {
    vector<string> argv;
    switch (method) {
        case Method::Dnf:
            argv = {"dnf", "remove", "-y", package};
            break;
        case Method::Pacman:
            argv = {"pacman", "-Rns", "--noconfirm", package};
            break;
        case Method::Apt:
            argv = {"apt-get", "remove", "-y", package};
            break;
        case Method::Aur:
            argv = {aur_helper(runner), "-Rns", "--noconfirm", package};
            break;
        case Method::Emerge:
            argv = {"emerge", "--unmerge", "--quiet", package};
            break;
        case Method::Our:
            our_remove(config, runner, package);
            return;
    }
    expect_ok(runner.run(argv), to_string(method) + " remove " + package);
}

void backend_upgrade(Method method, const optional<string> &package, const Config &config,
                     Runner &runner) {
    vector<string> argv;
    switch (method) {
        case Method::Dnf:
            argv = {"dnf", "upgrade", "-y"};
            break;
        case Method::Pacman:
            argv = package ? vector<string>{"pacman", "-S", "--needed", "--noconfirm", *package}
                           : vector<string>{"pacman", "-Syu", "--noconfirm"};
            break;
        case Method::Apt:
            argv = package ? vector<string>{"apt-get", "install", "-y", "--only-upgrade", *package}
                           : vector<string>{"apt-get", "upgrade", "-y"};
            break;
        case Method::Aur:
            argv = package ? vector<string>{aur_helper(runner), "-S", "--needed", "--noconfirm", *package}
                           : vector<string>{aur_helper(runner), "-Syu", "--noconfirm"};
            break;
        case Method::Emerge:
            argv = package ? vector<string>{"emerge", "-u", *package}
                           : vector<string>{"emerge", "-uDN", "@world"};
            break;
        case Method::Our:
            our_upgrade(config, runner, package);
            return;
    }
    if (method == Method::Dnf && package) {
        argv.push_back(*package);
    }
    expect_ok(runner.run(argv), to_string(method) + " upgrade");
}

vector<string> backend_check(Method method, const Config &config, Runner &runner) {
    if (method == Method::Our) {
        return our_updates(config);
    }
    vector<string> argv;
    switch (method) {
        case Method::Dnf:
            argv = {"dnf", "-q", "check-update"};
            break;
        case Method::Pacman:
            argv = {"pacman", "-Qu"};
            break;
        case Method::Apt:
            argv = {"apt", "list", "--upgradable"};
            break;
        case Method::Aur:
            argv = {aur_helper(runner), "-Qu"};
            break;
        case Method::Emerge:
            argv = {"emerge", "-puDN", "@world"};
            break;
        case Method::Our:
            return our_updates(config);
    }
    const RunResult result = runner.run(argv, false, true);
    vector<string> lines = non_empty_lines(result.output);
    if (method == Method::Dnf) {
        lines.erase(std::remove_if(lines.begin(), lines.end(),
                                   [](const string &line) {
                                       return line.rfind("Last metadata", 0) == 0;
                                   }),
                    lines.end());
    }
    if (method == Method::Apt) {
        lines.erase(std::remove_if(lines.begin(), lines.end(),
                                   [](const string &line) {
                                       return line.rfind("Listing", 0) == 0;
                                   }),
                    lines.end());
    }
    return lines;
}

vector<string> backend_list(Method method, const Config &config, Runner &runner) {
    if (method == Method::Our) {
        return our_installed(config);
    }
    vector<string> argv;
    switch (method) {
        case Method::Dnf:
            argv = {"dnf", "-q", "list", "--installed"};
            break;
        case Method::Pacman:
            argv = {"pacman", "-Q"};
            break;
        case Method::Apt:
            argv = {"dpkg-query", "-W", "-f=${binary:Package} ${Version}\\n"};
            break;
        case Method::Aur:
            argv = {aur_helper(runner), "-Q"};
            break;
        case Method::Emerge:
            if (runner.which("qlist")) {
                argv = {"qlist", "-IC"};
            }
            break;
        case Method::Our:
            return our_installed(config);
    }
    if (argv.empty()) {
        return {};
    }
    const RunResult result = runner.run(argv, false, true);
    vector<string> lines = non_empty_lines(result.output);
    if (method == Method::Dnf) {
        vector<string> parsed;
        for (const auto &line : lines) {
            const auto parts = split_ws(line);
            if (parts.size() < 2) {
                continue;
            }
            string name = parts[0];
            const auto dot = name.rfind('.');
            if (dot != string::npos) {
                name = name.substr(0, dot);
            }
            parsed.push_back(name + " " + parts[1]);
        }
        return parsed;
    }
    return lines;
}

vector<string> backend_search(Method method, const string &term, const Config &config,
                              Runner &runner, const string &prefix) {
    if (method == Method::Our) {
        vector<string> rows;
        for (const auto &pkg : search_our(config, term)) {
            rows.push_back(format_row(prefix, "our", pkg.name, pkg.version, pkg.description));
        }
        return rows;
    }

    vector<string> argv;
    switch (method) {
        case Method::Pacman:
            argv = {"pacman", "-Ss", term};
            break;
        case Method::Aur:
            argv = {aur_helper(runner), "-Ss", term};
            break;
        case Method::Dnf:
            argv = {"dnf", "-q", "search", term};
            break;
        case Method::Apt:
            argv = {"apt-cache", "search", term};
            break;
        case Method::Emerge:
            argv = {"emerge", "--search", term};
            break;
        case Method::Our:
            return {};
    }

    const RunResult result = runner.run(argv, false, true);
    vector<string> rows;
    string pending_name;
    string pending_version;

    for (const auto &line : non_empty_lines(result.output)) {
        if (method == Method::Pacman || method == Method::Aur) {
            const auto parts = split_ws(line);
            if (parts.size() >= 2 && parts[0].find('/') != string::npos) {
                string name = parts[0].substr(parts[0].find('/') + 1);
                string description;
                const auto name_pos = line.find(parts[1]);
                if (name_pos != string::npos) {
                    description = line.substr(name_pos + parts[1].size());
                }
                rows.push_back(format_row(prefix, to_string(method), name, parts[1],
                                          description));
            }
        } else if (method == Method::Dnf) {
            const auto separator = line.find(" : ");
            if (separator == string::npos) {
                continue;
            }
            const auto left = split_ws(line.substr(0, separator));
            if (left.empty()) {
                continue;
            }
            string name = left[0];
            const auto dot = name.rfind('.');
            if (dot != string::npos) {
                name = name.substr(0, dot);
            }
            const string version = left.size() > 1 ? left[1] : "";
            rows.push_back(format_row(prefix, "dnf", name, version, line.substr(separator + 3)));
        } else if (method == Method::Apt) {
            const auto separator = line.find(" - ");
            if (separator == string::npos) {
                continue;
            }
            rows.push_back(format_row(prefix, "apt", line.substr(0, separator), "",
                                      line.substr(separator + 3)));
        } else if (method == Method::Emerge) {
            const auto trimmed = line.substr(line.find_first_not_of(" \t"));
            if (trimmed.rfind("* ", 0) == 0) {
                const auto parts = split_ws(trimmed);
                if (!parts.empty()) {
                    pending_name = parts.back();
                }
            } else if (trimmed.rfind("Latest version available:", 0) == 0) {
                pending_version = trimmed.substr(trimmed.find(':') + 1);
                pending_version = pending_version.substr(
                    pending_version.find_first_not_of(" \t"));
            } else if (trimmed.rfind("Description:", 0) == 0) {
                rows.push_back(format_row(prefix, "emerge", pending_name, pending_version,
                                          trimmed.substr(trimmed.find(':') + 1)));
            }
        }
    }
    return rows;
}

vector<Method> backend_order(const Config &config, Runner &runner,
                             const optional<Method> &forced) {
    if (forced) {
        if (!backend_available(*forced, config, runner)) {
            throw Error("requested backend '" + to_string(*forced) +
                        "' is not available on this system");
        }
        return {*forced};
    }
    vector<Method> available;
    for (const auto &entry : kMethods) {
        if (backend_available(entry.method, config, runner)) {
            available.push_back(entry.method);
        }
    }
    std::sort(available.begin(), available.end(),
              [](Method left, Method right) { return priority(left) < priority(right); });
    return available;
}

vector<Method> candidates_for(const string &package, const Config &config, Runner &runner,
                              const optional<Method> &forced) {
    const vector<Method> order = backend_order(config, runner, forced);
    if (order.empty()) {
        throw Error("no supported package backend is available");
    }
    vector<Method> preferred;
    for (const auto method : order) {
        if (backend_has(method, package, config, runner)) {
            preferred.push_back(method);
        }
    }
    if (!preferred.empty()) {
        return preferred;
    }
    return order;
}

Method install_with_fallback(const string &package, const vector<Method> &candidates,
                             const Config &config, Runner &runner) {
    string failures;
    for (const auto method : candidates) {
        std::cout << "[omnom] " << package << ": trying " << label(method) << '\n';
        try {
            backend_install(method, package, config, runner);
            return method;
        } catch (const Error &error) {
            std::cerr << "[omnom] warning: " << error.what() << '\n';
            failures += " ";
            failures += to_string(method);
        }
    }
    throw Error("could not install " + package + " with any backend (tried:" + failures + ")");
}

}  // namespace omnom
