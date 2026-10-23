// Configuration loading for the Omnom package manager.

#include "common.hpp"

#include <cctype>
#include <cstdlib>
#include <fstream>
#include <sstream>

namespace omnom {
namespace {

string trim(const string &value) {
    const auto begin = value.find_first_not_of(" \t\r\n");
    if (begin == string::npos) {
        return "";
    }
    const auto end = value.find_last_not_of(" \t\r\n");
    return value.substr(begin, end - begin + 1);
}

string strip_quotes(const string &value) {
    if (value.size() >= 2) {
        const char first = value.front();
        const char last = value.back();
        if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
            return value.substr(1, value.size() - 2);
        }
    }
    return value;
}

string expand_home(const string &value) {
    const char *home = std::getenv("HOME");
    const string home_dir = home ? home : "";
    if (value == "~") {
        return home_dir;
    }
    if (value.rfind("~/", 0) == 0) {
        return home_dir + value.substr(1);
    }
    return value;
}

bool parse_bool(const string &key, const string &raw) {
    string value = raw;
    for (auto &character : value) {
        character = static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
    }
    if (value == "1" || value == "true" || value == "yes" || value == "on") {
        return true;
    }
    if (value == "0" || value == "false" || value == "no" || value == "off") {
        return false;
    }
    throw Error(key + ": expected true/false, got '" + raw + "'");
}

optional<string> env_value(const char *name) {
    const char *value = std::getenv(name);
    if (value == nullptr) {
        return std::nullopt;
    }
    return string(value);
}

string nproc() {
    std::ifstream cpuinfo("/proc/cpuinfo");
    int count = 0;
    string line;
    while (std::getline(cpuinfo, line)) {
        if (line.rfind("processor", 0) == 0) {
            ++count;
        }
    }
    if (count <= 0) {
        count = 1;
    }
    return "-j" + std::to_string(count);
}

}  // namespace

Config load_config(const optional<fs::path> &path) {
    Config config;

    const auto env_home = env_value("HOME");
    const string home = env_home ? *env_home : "/root";
    config.our_repo = fs::path(home) / ".config/omnom/our-repo";
    config.cache_dir = fs::path(home) / ".cache/omnom";
    config.makeopts = nproc();

    // Environment overrides take precedence over the file.
    const auto env_state = env_value("OMNOM_STATE_DIR");
    const auto env_profile = env_value("OMNOM_PROFILE_ROOT");
    const auto env_our = env_value("OMNOM_OUR_REPO");
    const auto env_cache = env_value("OMNOM_CACHE_DIR");
    const auto env_root = env_value("OMNOM_INSTALL_ROOT");
    const auto env_method = env_value("OMNOM_DEFAULT_METHOD");
    const auto env_keep = env_value("OMNOM_GENERATIONS_KEEP");
    const auto env_enabled = env_value("OMNOM_OUR_REPO_ENABLED");
    const auto env_dry = env_value("OMNOM_DRY_RUN");

    fs::path config_path;
    if (path) {
        config_path = *path;
    } else {
        const auto env_config = env_value("OMNOM_CONFIG");
        config_path = env_config ? fs::path(*env_config) : fs::path("/etc/omnom/omnom.conf");
    }

    if (!config_path.empty() && fs::exists(config_path)) {
        std::ifstream file(config_path);
        if (!file) {
            throw Error("cannot read " + config_path.string());
        }
        string line;
        int lineno = 0;
        while (std::getline(file, line)) {
            ++lineno;
            line = trim(line);
            if (line.empty() || line[0] == '#') {
                continue;
            }
            if (line.rfind("export ", 0) == 0) {
                line = trim(line.substr(7));
            }
            const auto equals = line.find('=');
            if (equals == string::npos) {
                throw Error(config_path.string() + ":" + std::to_string(lineno) +
                            ": expected KEY=VALUE");
            }
            const string key = trim(line.substr(0, equals));
            const string value = strip_quotes(trim(line.substr(equals + 1)));

            if (key == "STATE_DIR") {
                config.state_dir = value;
            } else if (key == "PROFILE_ROOT") {
                config.profile_root = value;
            } else if (key == "OUR_REPO") {
                config.our_repo = value;
            } else if (key == "CACHE_DIR") {
                config.cache_dir = value;
            } else if (key == "INSTALL_ROOT") {
                config.install_root = value;
            } else if (key == "DEFAULT_METHOD") {
                config.default_method = value;
            } else if (key == "GENERATIONS_KEEP") {
                try {
                    config.generations_keep = std::stoi(value);
                } catch (const std::exception &) {
                    throw Error("GENERATIONS_KEEP must be an integer, got '" + value + "'");
                }
            } else if (key == "CFLAGS") {
                config.cflags = value;
            } else if (key == "MAKEOPTS") {
                config.makeopts = value;
            } else if (key == "OUR_REPO_ENABLED") {
                config.our_repo_enabled = parse_bool(key, value);
            } else if (key == "AUTO_CLEANUP") {
                (void)parse_bool(key, value);
            } else if (key == "DRY_RUN") {
                config.dry_run = parse_bool(key, value);
            }
            // Unknown keys are ignored for forward compatibility.
        }
    }

    if (env_state) config.state_dir = *env_state;
    if (env_profile) config.profile_root = *env_profile;
    if (env_our) config.our_repo = *env_our;
    if (env_cache) config.cache_dir = *env_cache;
    if (env_root) config.install_root = *env_root;
    if (env_method) config.default_method = *env_method;
    if (env_keep) {
        try {
            config.generations_keep = std::stoi(*env_keep);
        } catch (const std::exception &) {
            throw Error("GENERATIONS_KEEP must be an integer, got '" + *env_keep + "'");
        }
    }
    if (env_enabled) config.our_repo_enabled = parse_bool("OUR_REPO_ENABLED", *env_enabled);
    if (env_dry) config.dry_run = parse_bool("DRY_RUN", *env_dry);

    config.state_dir = expand_home(config.state_dir.string());
    config.profile_root = expand_home(config.profile_root.string());
    config.our_repo = expand_home(config.our_repo.string());
    config.cache_dir = expand_home(config.cache_dir.string());
    config.install_root = expand_home(config.install_root.string());

    if (config.default_method != "auto" && config.default_method != "dnf" &&
        config.default_method != "pacman" && config.default_method != "apt" &&
        config.default_method != "aur" && config.default_method != "our" &&
        config.default_method != "emerge") {
        throw Error("DEFAULT_METHOD must be auto, dnf, pacman, apt, aur, our or emerge (got '" +
                    config.default_method + "')");
    }
    if (config.generations_keep < 1) {
        throw Error("GENERATIONS_KEEP must be at least 1");
    }
    return config;
}

}  // namespace omnom
