// Omnom User Repository: *.pkg recipes, source builds and file tracking.

#include "common.hpp"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <set>
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

bool valid_name(const string &name) {
    if (name.empty()) {
        return false;
    }
    if (!std::islower(static_cast<unsigned char>(name[0])) &&
        !std::isdigit(static_cast<unsigned char>(name[0]))) {
        return false;
    }
    for (const char character : name) {
        const auto value = static_cast<unsigned char>(character);
        if (!std::islower(value) && !std::isdigit(value) && character != '+' &&
            character != '.' && character != '_' && character != '-') {
            return false;
        }
    }
    return true;
}

bool valid_sha256(const string &value) {
    if (value.size() != 64) {
        return false;
    }
    for (const char character : value) {
        if (!std::isdigit(static_cast<unsigned char>(character)) &&
            !(character >= 'a' && character <= 'f')) {
            return false;
        }
    }
    return true;
}

string lower(string value) {
    for (auto &character : value) {
        character = static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
    }
    return value;
}

string sha256_of(const fs::path &file, Runner &runner) {
    RunResult result = runner.run({"sha256sum", file.string()}, false, true);
    if (!result.ok()) {
        result = runner.run({"shasum", "-a", "256", file.string()}, false, true);
    }
    if (!result.ok()) {
        throw Error("cannot compute sha256 of " + file.string());
    }
    const auto space = result.output.find(' ');
    return result.output.substr(0, space);
}

fs::path record_dir(const Config &config, const string &name) {
    return config.state_dir / "our" / name;
}

string read_first_line(const fs::path &path) {
    std::ifstream file(path);
    string line;
    std::getline(file, line);
    return line;
}

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

fs::path url_filename(const string &url) {
    string path = url;
    const auto query = path.find('?');
    if (query != string::npos) {
        path = path.substr(0, query);
    }
    const auto slash = path.rfind('/');
    if (slash != string::npos) {
        path = path.substr(slash + 1);
    }
    return fs::path(path);
}

fs::path locate_source_dir(const fs::path &root) {
    fs::path only_directory;
    int entries = 0;
    for (const auto &entry : fs::directory_iterator(root)) {
        ++entries;
        if (entry.is_directory()) {
            only_directory = entry.path();
        }
    }
    if (entries == 1 && !only_directory.empty()) {
        return only_directory;
    }
    return root;
}

}  // namespace

Pkg parse_pkg(const fs::path &path) {
    std::ifstream file(path);
    if (!file) {
        throw Error("cannot read " + path.string());
    }

    Pkg pkg;
    pkg.path = path;
    string line;
    while (std::getline(file, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') {
            continue;
        }
        const auto equals = line.find('=');
        if (equals == string::npos) {
            throw Error(path.string() + ": expected KEY=VALUE");
        }
        const string key = trim(line.substr(0, equals));
        const string value = strip_quotes(trim(line.substr(equals + 1)));

        if (key == "name") {
            pkg.name = value;
        } else if (key == "version") {
            pkg.version = value;
        } else if (key == "description") {
            pkg.description = value;
        } else if (key == "source") {
            pkg.source = value;
        } else if (key == "sha256") {
            pkg.sha256 = value;
        } else if (key == "build") {
            pkg.build = value;
        } else if (key == "install") {
            pkg.install = value;
        } else if (key == "depends") {
            pkg.depends = value;
        } else if (key == "homepage") {
            pkg.homepage = value;
        } else {
            throw Error(path.string() + ": unknown key '" + key + "'");
        }
    }

    if (pkg.name.empty()) {
        throw Error(path.string() + ": missing 'name'");
    }
    if (pkg.version.empty()) {
        throw Error(path.string() + ": missing 'version'");
    }
    if (!valid_name(pkg.name)) {
        throw Error(path.string() + ": invalid package name '" + pkg.name + "'");
    }
    if (path.stem().string() != pkg.name) {
        throw Error(path.string() + ": file name must be " + pkg.name + ".pkg");
    }
    if (!pkg.source.empty()) {
        if (pkg.sha256.empty()) {
            throw Error(path.string() + ": 'source' requires 'sha256'");
        }
        if (!valid_sha256(pkg.sha256)) {
            throw Error(path.string() + ": sha256 must be 64 lowercase hex characters");
        }
    }
    return pkg;
}

vector<Pkg> scan_repo(const fs::path &repo) {
    vector<Pkg> packages;
    std::error_code ec;
    if (!fs::is_directory(repo, ec)) {
        return packages;
    }
    vector<fs::path> files;
    for (const auto &entry : fs::directory_iterator(repo, ec)) {
        if (entry.path().extension() == ".pkg") {
            files.push_back(entry.path());
        }
    }
    std::sort(files.begin(), files.end());
    std::set<string> seen;
    for (const auto &file : files) {
        Pkg pkg = parse_pkg(file);
        if (!seen.insert(pkg.name).second) {
            throw Error("duplicate package '" + pkg.name + "' in " + repo.string());
        }
        packages.push_back(std::move(pkg));
    }
    return packages;
}

optional<Pkg> find_pkg(const fs::path &repo, const string &name) {
    for (const auto &pkg : scan_repo(repo)) {
        if (pkg.name == name) {
            return pkg;
        }
    }
    return std::nullopt;
}

vector<Pkg> search_our(const Config &config, const string &term) {
    vector<Pkg> found;
    const string needle = lower(term);
    for (const auto &pkg : scan_repo(config.our_repo)) {
        if (lower(pkg.name + " " + pkg.description).find(needle) != string::npos) {
            found.push_back(pkg);
        }
    }
    return found;
}

void our_install(const Config &config, Runner &runner, const string &name) {
    const auto package = find_pkg(config.our_repo, name);
    if (!package) {
        throw Error("'" + name + "' is not in " + config.our_repo.string());
    }

    const string build = package->build.empty() ? "./configure --prefix=/usr && make"
                                                : package->build;
    const string install = package->install.empty()
                               ? "make install DESTDIR=\"$DESTDIR\""
                               : package->install;

    if (runner.dry_run()) {
        std::cout << "[dry-run] our: build " << package->name << ' ' << package->version << '\n'
                  << "[dry-run] our: source " << (package->source.empty() ? "<local build>" : package->source) << '\n'
                  << "[dry-run] our: build command: " << build << '\n'
                  << "[dry-run] our: install command: " << install << '\n'
                  << "[dry-run] our: install root " << config.install_root.string() << '\n';
        return;
    }

    string work_template = (fs::temp_directory_path() /
                            ("omnom-build-" + package->name + "-XXXXXX"))
                               .string();
    vector<char> template_buffer(work_template.begin(), work_template.end());
    template_buffer.push_back('\0');
    if (mkdtemp(template_buffer.data()) == nullptr) {
        throw Error("cannot create a temporary build directory");
    }
    const fs::path work_dir(template_buffer.data());

    struct Cleanup {
        fs::path path;
        ~Cleanup() {
            std::error_code ec;
            fs::remove_all(path, ec);
        }
    } cleanup{work_dir};

    fs::path source_dir = work_dir;
    if (!package->source.empty()) {
        fs::path archive_name = url_filename(package->source);
        if (archive_name.empty()) {
            archive_name = package->name + "-" + package->version + ".tar.gz";
        }
        const fs::path archive = config.cache_dir / "our" / archive_name;
        fs::create_directories(archive.parent_path());

        bool cached = false;
        if (fs::exists(archive)) {
            cached = sha256_of(archive, runner) == package->sha256;
        }
        if (!cached) {
            const fs::path partial = archive.string() + ".part";
            std::cout << "[our] downloading " << package->source << '\n';
            RunResult download;
            if (runner.which("curl")) {
                download = runner.run({"curl", "-fsSL", "--retry", "3", "-o", partial.string(),
                                       package->source}, false, false);
            } else if (runner.which("wget")) {
                download = runner.run({"wget", "-q", "-O", partial.string(), package->source},
                                      false, false);
            } else {
                throw Error("curl or wget is required to download OUR sources");
            }
            if (!download.ok()) {
                fs::remove(partial);
                throw Error("download failed: " + package->source);
            }
            const string actual = sha256_of(partial, runner);
            if (actual != package->sha256) {
                fs::remove(partial);
                throw Error("sha256 mismatch for " + package->source + " (expected " +
                            package->sha256 + ", got " + actual + ")");
            }
            fs::rename(partial, archive);
        } else {
            std::cout << "[our] using cached " << archive.string() << '\n';
        }

        const fs::path extract_dir = work_dir / "src";
        fs::create_directories(extract_dir);
        const string archive_string = archive.string();
        RunResult extraction;
        if (archive.extension() == ".zip") {
            extraction = runner.run({"unzip", "-q", archive_string, "-d", extract_dir.string()},
                                    false, false);
        } else {
            extraction = runner.run({"tar", "-xf", archive_string, "-C", extract_dir.string()},
                                    false, false);
        }
        if (!extraction.ok()) {
            throw Error("cannot extract " + archive.string());
        }
        source_dir = locate_source_dir(extract_dir);
    }

    const fs::path stage = work_dir / "stage";
    fs::create_directories(stage);
    const vector<std::pair<string, string>> environment{
        {"DESTDIR", stage.string()},
        {"PREFIX", "/usr"},
        {"CFLAGS", config.cflags},
        {"CXXFLAGS", config.cflags},
        {"MAKEFLAGS", config.makeopts},
    };

    std::cout << "[our] building " << package->name << ' ' << package->version << '\n';
    const RunResult build_result = runner.shell(build, source_dir, environment);
    if (!build_result.ok()) {
        throw Error("build of " + package->name + " failed");
    }
    const RunResult install_result = runner.shell(install, source_dir, environment);
    if (!install_result.ok()) {
        throw Error("install of " + package->name + " failed");
    }

    vector<string> files;
    std::error_code ec;
    for (const auto &entry : fs::recursive_directory_iterator(stage, ec)) {
        const fs::path relative = fs::relative(entry.path(), stage);
        if (relative.empty()) {
            continue;
        }
        const fs::path target = config.install_root / relative;
        std::cout << "[our] → " << target.string() << '\n';
        if (entry.is_symlink()) {
            fs::create_directories(target.parent_path(), ec);
            fs::remove(target, ec);
            fs::create_symlink(fs::read_symlink(entry.path()), target, ec);
            files.push_back(relative.string());
        } else if (entry.is_directory()) {
            fs::create_directories(target, ec);
        } else if (entry.is_regular_file()) {
            fs::create_directories(target.parent_path(), ec);
            fs::copy_file(entry.path(), target, fs::copy_options::overwrite_existing, ec);
            fs::permissions(target, fs::status(entry.path()).permissions(), ec);
            files.push_back(relative.string());
        } else {
            std::cerr << "[omnom] warning: skipping special file " << relative.string() << '\n';
        }
        if (ec) {
            throw Error("cannot install " + relative.string() + ": " + ec.message());
        }
    }

    std::sort(files.begin(), files.end());
    const fs::path record = record_dir(config, package->name);
    fs::create_directories(record);
    {
        std::ofstream list(record / "files", std::ios::trunc);
        for (const auto &file : files) {
            list << file << '\n';
        }
    }
    {
        std::ofstream version(record / "version", std::ios::trunc);
        version << package->version << '\n';
    }
    {
        std::ofstream depends(record / "depends", std::ios::trunc);
        string normalised = package->depends;
        std::replace(normalised.begin(), normalised.end(), ',', ' ');
        std::istringstream stream(normalised);
        string item;
        while (stream >> item) {
            depends << item << '\n';
        }
    }
    std::cout << "[omnom] installed " << package->name << ' ' << package->version << " ("
              << files.size() << " file(s))\n";
}

void our_remove(const Config &config, Runner &runner, const string &name) {
    const fs::path record = record_dir(config, name);
    if (!fs::is_directory(record)) {
        throw Error("no OUR installation record for '" + name + "'");
    }
    const vector<string> files = read_lines(record / "files");
    if (runner.dry_run()) {
        for (const auto &file : files) {
            std::cout << "[dry-run] remove " << (config.install_root / file).string() << '\n';
        }
        return;
    }
    std::error_code ec;
    for (const auto &file : files) {
        const fs::path target = config.install_root / file;
        fs::remove(target, ec);
        fs::path parent = target.parent_path();
        while (parent != config.install_root && fs::is_directory(parent, ec) &&
               fs::is_empty(parent, ec)) {
            if (!fs::remove(parent, ec)) {
                break;
            }
            parent = parent.parent_path();
        }
    }
    fs::remove_all(record, ec);
    std::cout << "[omnom] removed " << name << '\n';
}

vector<string> our_installed(const Config &config) {
    vector<string> entries;
    std::error_code ec;
    const fs::path root = config.state_dir / "our";
    if (!fs::is_directory(root, ec)) {
        return entries;
    }
    for (const auto &entry : fs::directory_iterator(root, ec)) {
        if (!entry.is_directory()) {
            continue;
        }
        const string name = entry.path().filename().string();
        entries.push_back(name + " " + read_first_line(entry.path() / "version"));
    }
    std::sort(entries.begin(), entries.end());
    return entries;
}

vector<string> our_updates(const Config &config) {
    vector<string> updates;
    std::error_code ec;
    const fs::path root = config.state_dir / "our";
    if (!fs::is_directory(root, ec)) {
        return updates;
    }
    for (const auto &entry : fs::directory_iterator(root, ec)) {
        if (!entry.is_directory()) {
            continue;
        }
        const string name = entry.path().filename().string();
        const auto package = find_pkg(config.our_repo, name);
        if (!package) {
            continue;
        }
        const string current = read_first_line(entry.path() / "version");
        if (!current.empty() && current != package->version) {
            updates.push_back(name + " " + current + " -> " + package->version);
        }
    }
    std::sort(updates.begin(), updates.end());
    return updates;
}

void our_upgrade(const Config &config, Runner &runner, const optional<string> &name) {
    vector<string> names;
    if (name) {
        names.push_back(*name);
    } else {
        for (const auto &entry : our_installed(config)) {
            names.push_back(entry.substr(0, entry.find(' ')));
        }
    }
    if (names.empty()) {
        std::cout << "[omnom] no OUR packages installed\n";
        return;
    }
    for (const auto &package_name : names) {
        const auto package = find_pkg(config.our_repo, package_name);
        if (!package) {
            std::cerr << "[omnom] warning: " << package_name
                      << " is no longer in the repository, skipping\n";
            continue;
        }
        const string current = read_first_line(record_dir(config, package_name) / "version");
        if (current == package->version) {
            std::cout << "[omnom] " << package_name << ' ' << current << " is up to date\n";
            continue;
        }
        std::cout << "[omnom] upgrading " << package_name << ' ' << current << " -> "
                  << package->version << '\n';
        our_install(config, runner, package_name);
    }
}

}  // namespace omnom
