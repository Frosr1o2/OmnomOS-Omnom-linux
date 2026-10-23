// Generations, package records and history.

#include "common.hpp"

#include <algorithm>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <set>
#include <sstream>

namespace omnom {
namespace {

vector<string> read_lines(const fs::path &path) {
    vector<string> lines;
    std::ifstream file(path);
    string line;
    while (std::getline(file, line)) {
        if (!line.empty()) {
            lines.push_back(line);
        }
    }
    return lines;
}

void write_lines(const fs::path &path, const vector<string> &lines) {
    fs::create_directories(path.parent_path());
    const fs::path temporary = path.string() + ".tmp";
    {
        std::ofstream file(temporary, std::ios::trunc);
        if (!file) {
            throw Error("cannot write " + temporary.string());
        }
        for (const auto &line : lines) {
            file << line << '\n';
        }
    }
    fs::rename(temporary, path);
}

string utc_timestamp(const char *format) {
    const std::time_t now = std::time(nullptr);
    std::tm utc{};
    gmtime_r(&now, &utc);
    char buffer[32];
    std::strftime(buffer, sizeof buffer, format, &utc);
    return buffer;
}

bool starts_with(const string &value, const string &prefix) {
    return value.rfind(prefix, 0) == 0;
}

}  // namespace

State::State(const Config &config) : config_(config) {}

void State::ensure() const {
    fs::create_directories(config_.state_dir / "generations");
}

void State::history(const string &message) const {
    ensure();
    std::ofstream file(config_.state_dir / "history.log", std::ios::app);
    file << utc_timestamp("%Y-%m-%dT%H:%M:%SZ") << ' ' << message << '\n';
}

vector<string> State::packages() const {
    return read_lines(packages_file());
}

void State::add_packages(const vector<string> &names) const {
    const vector<string> current = packages();
    std::set<string> unique(current.begin(), current.end());
    for (const auto &name : names) {
        unique.insert(name);
    }
    write_lines(packages_file(), vector<string>(unique.begin(), unique.end()));
}

void State::drop_packages(const vector<string> &names) const {
    std::set<string> doomed;
    for (const auto &name : names) {
        doomed.insert(name.substr(0, name.find(' ')));
    }
    std::set<string> remaining;
    for (const auto &entry : packages()) {
        if (doomed.count(entry.substr(0, entry.find(' '))) == 0) {
            remaining.insert(entry);
        }
    }
    write_lines(packages_file(), vector<string>(remaining.begin(), remaining.end()));
}

bool State::tracked(const string &package) const {
    for (const auto &entry : packages()) {
        if (entry == package || starts_with(entry, package + " ")) {
            return true;
        }
    }
    return false;
}

string State::managed_get(const string &package) const {
    for (const auto &entry : read_lines(managed_file())) {
        const auto space = entry.find(' ');
        if (space != string::npos && entry.substr(0, space) == package) {
            return entry.substr(space + 1);
        }
    }
    return "";
}

void State::managed_set(const string &package, const string &method) const {
    vector<string> entries;
    for (const auto &entry : read_lines(managed_file())) {
        if (starts_with(entry, package + " ")) {
            continue;
        }
        entries.push_back(entry);
    }
    entries.push_back(package + " " + method);
    std::sort(entries.begin(), entries.end());
    write_lines(managed_file(), entries);
}

void State::managed_del(const string &package) const {
    vector<string> entries;
    for (const auto &entry : read_lines(managed_file())) {
        if (!starts_with(entry, package + " ")) {
            entries.push_back(entry);
        }
    }
    write_lines(managed_file(), entries);
}

vector<string> State::generation_names() const {
    vector<string> names;
    const fs::path dir = generations_dir();
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) {
        return names;
    }
    for (const auto &entry : fs::directory_iterator(dir, ec)) {
        const string name = entry.path().filename().string();
        if (entry.is_directory() && starts_with(name, "gen-")) {
            names.push_back(name);
        }
    }
    std::sort(names.begin(), names.end(), std::greater<>());
    return names;
}

bool State::generation_exists(const string &name) const {
    std::error_code ec;
    return !name.empty() && fs::is_directory(generations_dir() / name, ec);
}

optional<string> State::current_generation() const {
    const fs::path link = generations_dir() / "current";
    std::error_code ec;
    if (!fs::is_symlink(link, ec)) {
        return std::nullopt;
    }
    return fs::read_symlink(link).filename().string();
}

string State::generation_meta(const string &name, const string &key) const {
    std::ifstream file(generations_dir() / name / "meta");
    string line;
    while (std::getline(file, line)) {
        const auto equals = line.find('=');
        if (equals != string::npos && line.substr(0, equals) == key) {
            return line.substr(equals + 1);
        }
    }
    return "";
}

string State::create_generation(const string &reason, const string &method) const {
    ensure();
    const string stamp = utc_timestamp("%Y%m%d_%H%M%S");
    string name = "gen-" + stamp;
    int suffix = 1;
    while (generation_exists(name)) {
        ++suffix;
        name = "gen-" + stamp + "_" + std::to_string(suffix);
    }

    const fs::path dir = generations_dir() / name;
    fs::create_directories(dir);

    const auto current = current_generation();
    const vector<string> tracked = packages();
    write_lines(dir / "packages.list", tracked);
    write_lines(dir / "managed.list", read_lines(managed_file()));
    {
        std::ofstream meta(dir / "meta", std::ios::trunc);
        meta << "name=" << name << '\n'
             << "created=" << utc_timestamp("%Y-%m-%dT%H:%M:%SZ") << '\n'
             << "reason=" << reason << '\n'
             << "method=" << method << '\n'
             << "parent=" << (current ? *current : "") << '\n';
    }

    const fs::path link = generations_dir() / "current";
    std::error_code ec;
    fs::remove(link, ec);
    fs::create_symlink(name, link);
    profile_sync(dir);

    history(name + " created: " + reason + " (method=" + method +
            ", packages=" + std::to_string(tracked.size()) + ")");
    prune();
    return name;
}

void State::switch_generation(const string &name) const {
    if (!generation_exists(name)) {
        throw Error("generation '" + name + "' does not exist");
    }
    const fs::path dir = generations_dir() / name;
    const fs::path link = generations_dir() / "current";
    std::error_code ec;
    fs::remove(link, ec);
    fs::create_symlink(name, link);

    const vector<string> recorded = read_lines(dir / "packages.list");
    if (fs::exists(dir / "packages.list")) {
        write_lines(packages_file(), recorded);
    } else {
        write_lines(packages_file(), {});
    }
    if (fs::exists(dir / "managed.list")) {
        write_lines(managed_file(), read_lines(dir / "managed.list"));
    } else {
        write_lines(managed_file(), {});
    }
    profile_sync(dir);
    history("switched to " + name);
}

void State::profile_sync(const fs::path &generation_path) const {
    if (config_.profile_root.empty()) {
        return;
    }
    std::error_code ec;
    fs::create_directories(config_.profile_root, ec);
    if (ec) {
        std::cerr << "[omnom] warning: cannot create " << config_.profile_root.string()
                  << ": " << ec.message() << '\n';
        return;
    }
    const fs::path link = config_.profile_root / "current";
    fs::remove(link, ec);
    fs::create_symlink(fs::absolute(generation_path), link, ec);
    if (ec) {
        std::cerr << "[omnom] warning: cannot update " << link.string() << ": "
                  << ec.message() << '\n';
    }
}

optional<string> State::previous_generation() const {
    const auto current = current_generation();
    for (const auto &name : generation_names()) {
        if (!current || name != *current) {
            return name;
        }
    }
    return std::nullopt;
}

void State::prune() const {
    const auto current = current_generation();
    int index = 0;
    for (const auto &name : generation_names()) {
        ++index;
        if (index <= config_.generations_keep) {
            continue;
        }
        if (current && name == *current) {
            continue;
        }
        std::error_code ec;
        fs::remove_all(generations_dir() / name, ec);
        history("pruned " + name);
    }
}

void State::print_generations() const {
    const auto names = generation_names();
    const auto current = current_generation();
    if (names.empty()) {
        std::cout << "[omnom] no generations recorded yet\n";
        return;
    }
    std::cout << "  " << std::left << std::setw(24) << "GENERATION" << ' ' << std::setw(20)
              << "CREATED (UTC)" << ' ' << std::right << std::setw(8) << "PACKAGES" << "  "
              << std::left << "REASON" << '\n';
    for (const auto &name : names) {
        const auto count = read_lines(generations_dir() / name / "packages.list").size();
        string created = generation_meta(name, "created");
        if (!created.empty() && created.back() == 'Z') {
            created.pop_back();
        }
        std::cout << (current && name == *current ? '*' : ' ') << ' ' << std::left
                  << std::setw(24) << name << ' ' << std::setw(20) << created << ' '
                  << std::right << std::setw(8) << count << "  " << std::left
                  << generation_meta(name, "reason") << '\n';
    }
}

}  // namespace omnom
