import doit
import shutil
import logging
import os
import subprocess as sp
import pathlib
import contextlib
from . import wlutil
from . import launch as wllaunch

taskLoader = None


class BuildrootSourceError(Exception):
    """Raised when a Buildroot-managed source tree is unavailable."""


def _buildroot_dir():
    """Return the Buildroot tree selected by the active FireMarshal board."""
    return pathlib.Path(os.environ.get(
        'FIREMARSHAL_BUILDROOT_DIR', wlutil.getOpt('buildroot-dir'))).resolve()


def _buildroot_config_value(name):
    buildroot_dir = _buildroot_dir()
    config_paths = [buildroot_dir / '.config', buildroot_dir / 'output' / '.config']

    for config_path in config_paths:
        if not config_path.is_file():
            continue

        with open(config_path, 'r') as config_file:
            for line in config_file:
                key, separator, value = line.rstrip('\n').partition('=')
                if separator and key == name:
                    return value.strip().strip('"')

    raise BuildrootSourceError(
        f"Buildroot configuration does not define {name}. "
        "Build the workload root filesystem before building its payload.")


def _buildroot_package_source(package, version_option):
    version = _buildroot_config_value(version_option)
    source = _buildroot_dir() / 'output' / 'build' / f"{package}-{version}"
    if not source.is_dir():
        raise BuildrootSourceError(
            f"Buildroot has not extracted {package} ({version}) at {source}. "
            "Build the workload root filesystem before building its payload.")
    return source


def _private_buildroot_source(source, destination, clean_target):
    """Copy a Buildroot package source into a clean workload-private tree."""
    extracted_stamp = source / '.stamp_extracted'
    fingerprint = f"v2:{source.resolve()}:{extracted_stamp.stat().st_mtime_ns}"
    fingerprint_file = destination.parent / f".{destination.name}.buildroot-source"

    if destination.is_dir() and fingerprint_file.is_file():
        if fingerprint_file.read_text().strip() == fingerprint:
            return destination

    if destination.exists():
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sp.run(['cp', '-a', '--reflink=auto', str(source), str(destination)], check=True)
    clean_args = ['make', clean_target]
    if clean_target == 'mrproper':
        clean_args.insert(1, 'ARCH=riscv')
    wlutil.run(clean_args, cwd=destination)
    fingerprint_file.write_text(fingerprint + '\n')
    return destination


def _buildroot_busybox_source():
    build_dir = _buildroot_dir() / 'output' / 'build'
    candidates = [
        candidate for candidate in build_dir.glob('busybox-*')
        if candidate.is_dir() and (candidate / '.config').is_file()
    ]
    if not candidates:
        raise BuildrootSourceError(
            f"Buildroot has not built BusyBox under {build_dir}. "
            "Build the workload root filesystem before building its payload.")

    return max(candidates, key=lambda candidate: (candidate / '.config').stat().st_mtime_ns)


def _buildroot_busybox_binary():
    target_dir = _buildroot_dir() / 'output' / 'target'
    for relative_path in [pathlib.Path('usr/bin/busybox'), pathlib.Path('bin/busybox')]:
        binary = target_dir / relative_path
        if binary.is_file():
            return binary

    raise BuildrootSourceError(
        f"Buildroot has not installed BusyBox under {target_dir}. "
        "Build the workload root filesystem before building its payload.")


def prepareBuildrootSources(config):
    """Resolve Buildroot package sources and use workload-private build trees."""

    linux = config['linux']
    firmware = config['firmware']

    if 'source' not in linux:
        source = _buildroot_package_source('linux', 'BR2_LINUX_KERNEL_VERSION')
        # Buildroot builds Linux in its extracted source directory. FireMarshal
        # uses O= and therefore needs a clean, private source tree.
        linux['source'] = _private_buildroot_source(
            source, config['out-dir'] / 'linux-source', 'mrproper')
    if not linux['source'].is_dir():
        raise BuildrootSourceError(f"Linux source directory does not exist: {linux['source']}")

    if 'source' not in firmware:
        source = _buildroot_package_source('opensbi', 'BR2_TARGET_OPENSBI_VERSION')
        firmware['source'] = _private_buildroot_source(
            source, config['out-dir'] / 'opensbi-source', 'distclean')
    if not firmware['source'].is_dir():
        raise BuildrootSourceError(f"OpenSBI source directory does not exist: {firmware['source']}")

    linux['build-dir'] = config['out-dir'] / 'linux-build'
    firmware['build-dir'] = config['out-dir'] / 'opensbi-build'


# Print task target or file dep changes
# Taken from: https://github.com/pydoit/doit/issues/329
def print_deps(task, changed):
    log = logging.getLogger()
    for t in task.targets:
        if not os.path.exists(t):
            log.debug(f"Running task {task.name} because one of its targets does not exist anymore: {t}")
            return

    if changed:
        log.debug(f"Running task {task.name} because the following changed: {changed}")


class doitLoader(doit.cmd_base.TaskLoader2):
    workloads = []

    # Idempotent add (no duplicates)
    def addTask(self, tsk):
        if not any(t['name'] == tsk['name'] for t in self.workloads):
            # add dep. tracker to each task
            tsk['actions'] = [print_deps] + tsk['actions']
            self.workloads.append(tsk)

    def load_doit_config(self):
        return {**wlutil.getOpt('doitOpts'), **{'check_file_uptodate': wlutil.WithMetadataChecker}}

    def load_tasks(self, cmd, pos_args):
        task_list = [doit.task.dict_to_task(w) for w in self.workloads]
        return task_list


def buildBusybox(config):
    """Copy Buildroot's BusyBox into FireMarshal's private initramfs."""
    try:
        busybox = _buildroot_busybox_binary()
    except BuildrootSourceError as e:
        return doit.exceptions.TaskFailed(e)

    shutil.copy(busybox, wlutil.getOpt('initramfs-dir') / 'disk' / 'bin/')
    shutil.copy(busybox, wlutil.getOpt('initramfs-dir') / 'nodisk' / 'fm-init/')
    return True


def handleHostInit(config):
    log = logging.getLogger()
    if 'host-init' in config:
        log.debug("Applying host-init: " + str(config['host-init']))
        if not config['host-init'].path.exists():
            raise ValueError("host-init script " + str(config['host-init']) + " not found.")

        wlutil.run([config['host-init'].path] + config['host-init'].args, cwd=config['workdir'])


def handlePostBin(config, linuxBin):
    log = logging.getLogger()
    if 'post-bin' in config:
        log.debug("Applying post-bin: " + str(config['post-bin']))
        if not config['post-bin'].path.exists():
            raise ValueError("post-bin script " + str(config['post-bin']) + " not found.")

        # add linux src and bin path to the environment
        postbinEnv = os.environ.copy()
        if 'linux' in config:
            postbinEnv.update({'FIREMARSHAL_LINUX_SRC': config['linux']['source'].as_posix()})
            postbinEnv.update({'FIREMARSHAL_LINUX_BIN': linuxBin})

        wlutil.run([config['post-bin'].path] + config['post-bin'].args, env=postbinEnv, cwd=config['workdir'])


def fileDepsTask(name, taskDeps=None, overlay=None, files=None):
    """Returns a task dict for a calc_dep task that calculates the file
    dependencies represented by an overlay and/or a list of FileSpec objects.
    Either can be None.

    taskDeps should be a list of names of tasks that must run before
    calculating dependencies (e.g. host-init)"""

    def fileDeps(overlay, files):
        """The python-action for the filedeps task, returns a dictionary of dependencies"""
        deps = []
        if overlay is not None:
            deps.append(overlay)

        if files is not None:
            deps += [f.src for f in files if not f.src.is_symlink()]

        for dep in deps.copy():
            if dep.is_dir():
                deps += [child for child in dep.glob('**/*') if not child.is_symlink()]

        return {'file_dep': [str(f) for f in deps if not f.is_dir()]}

    task = {'name': 'calc_' + name + '_dep',
            'actions': [(fileDeps, [overlay, files])]}

    if taskDeps is not None:
        task['task_dep'] = taskDeps

    return task


def addDep(loader, config):
    """Adds 'config' to the doit dependency graph ('loader')"""

    # Linux-based workloads depend on this task
    loader.addTask({
        'name': 'build_busybox',
        'actions': [(buildBusybox, [config])],
        'targets': [wlutil.getOpt('initramfs-dir') / 'disk' / 'bin' / 'busybox',
                    wlutil.getOpt('initramfs-dir') / 'nodisk' / 'fm-init' / 'busybox'],
        'file_dep': [wlutil.getOpt('wlutil-dir') / 'busybox-config'],
        'task_dep': config['base-deps'],
        'uptodate': [wlutil.config_changed(wlutil.getToolVersions())]
        })

    hostInit = []
    # Host-init task always runs because we can't tell if its uptodate and we
    # don't know its inputs/outputs.
    if 'host-init' in config:
        loader.addTask({
            'name': str(config['host-init']),
            'actions': [(handleHostInit, [config])],
        })
        hostInit = [str(config['host-init'])]

    # Add a rule for the binary
    bin_file_deps = []
    bin_task_deps = [] + hostInit + config['base-deps']
    bin_targets = []
    if 'linux' in config:
        bin_file_deps += config['linux']['config']
        bin_task_deps.append('build_busybox')
        bin_targets.append(config['dwarf'])

    if config['use-parent-bin']:
        bin_task_deps.append(str(config['base-bin']))

    diskBin = []
    if 'bin' in config:
        if 'dwarf' in config:
            targets = [str(config['bin']), str(config['dwarf'])]
        else:
            targets = [str(config['bin'])]

        loader.addTask({
                'name': str(config['bin']),
                'actions': [(makeBin, [config])],
                'targets': targets,
                'file_dep': bin_file_deps,
                'task_dep': bin_task_deps
                })
        diskBin = [str(config['bin'])]

    # Add a rule for the nodisk version if requested
    nodiskBin = []
    if config['nodisk'] and 'bin' in config:
        nodisk_file_deps = bin_file_deps.copy()
        nodisk_task_deps = bin_task_deps.copy()
        if 'img' in config:
            nodisk_file_deps.append(config['img'])
            nodisk_task_deps.append(str(config['img']))

        if 'dwarf' in config:
            targets = [str(wlutil.noDiskPath(config['bin'])), str(wlutil.noDiskPath(config['dwarf']))]
        else:
            targets = [str(wlutil.noDiskPath(config['bin']))]

        loader.addTask({
                'name': str(wlutil.noDiskPath(config['bin'])),
                'actions': [(makeBin, [config], {'nodisk': True})],
                'targets': targets,
                'file_dep': nodisk_file_deps,
                'task_dep': nodisk_task_deps
                })
        nodiskBin = [str(wlutil.noDiskPath(config['bin']))]

    # Add a rule for running script after binary is created (i.e. for ext. modules)
    # Similar to 'host-init' always runs if exists
    postBin = []
    post_bin_task_deps = diskBin + nodiskBin  # also used to get the bin path
    if 'post-bin' in config:
        loader.addTask({
            'name': str(config['post-bin']),
            'actions': [(handlePostBin, [config, post_bin_task_deps[0]])],
            'task_dep': post_bin_task_deps,
        })
        postBin = [str(config['post-bin'])]

    # Add a rule for the image (if any)
    img_file_deps = []
    img_task_deps = [] + hostInit + postBin + config['base-deps']
    img_calc_deps = []
    img_uptodate = []
    if 'img' in config:
        if 'base-img' in config:
            img_file_deps.append(config['base-img'])

        if 'files' in config or 'overlay' in config:
            # We delay calculation of files and overlay dependencies to runtime
            # in order to catch any generated inputs
            fdepsTask = fileDepsTask(config['name'], taskDeps=img_task_deps,
                                     overlay=config.get('overlay'),
                                     files=config.get('files'))
            img_calc_deps.append(fdepsTask['name'])
            loader.addTask(fdepsTask)
        if 'guest-init' in config:
            img_file_deps.append(config['guest-init'].path)
            img_task_deps.append(str(config['bin']))
        if 'runSpec' in config and config['runSpec'].path is not None:
            img_file_deps.append(config['runSpec'].path)
        if 'cfg-file' in config:
            img_file_deps.append(config['cfg-file'])
        if 'distro' in config:
            img_uptodate += config['builder'].upToDate()

        loader.addTask({
            'name': str(config['img']),
            'actions': [(makeImage, [config])],
            'targets': [config['img']],
            'file_dep': img_file_deps,
            'task_dep': img_task_deps,
            'calc_dep': img_calc_deps,
            'uptodate': img_uptodate
            })


# Generate a task-graph loader for the doit "Run" command
# Note: this doesn't depend on the config or runtime args at all. In theory, it
# could be cached, but I'm not going to bother unless it becomes a performance
# issue.
def buildDepGraph(cfgs):
    loader = doitLoader()

    for cfgPath in cfgs.keys():
        config = cfgs[cfgPath]

        if config['isDistro'] and 'img' in config:
            loader.addTask({
                    'name': str(config['img']),
                    'actions': [(config['builder'].buildBaseImage)],
                    'targets': [config['img']],
                    'file_dep': config['builder'].fileDeps(),
                    'uptodate': (config['builder'].upToDate() +
                                 [wlutil.config_changed(wlutil.getToolVersions())])
            })
        else:
            addDep(loader, config)

            if 'jobs' in config.keys():
                for jCfg in config['jobs'].values():
                    addDep(loader, jCfg)

    return loader


def buildWorkload(cfgName, cfgs, buildBin=True, buildImg=True):
    # This should only be built once (multiple builds will mess up doit)
    global taskLoader
    if taskLoader is None:
        taskLoader = buildDepGraph(cfgs)

    config = cfgs[cfgName]

    imgList = []
    binList = []

    if buildBin and 'bin' in config:
        if config['nodisk']:
            binList.append(wlutil.noDiskPath(config['bin']))
        else:
            binList.append(config['bin'])

    if 'img' in config and buildImg and not config['img-hardcoded']:
        imgList.append(config['img'])

    if 'jobs' in config.keys():
        for jCfg in config['jobs'].values():
            if buildBin:
                binList.append(jCfg['bin'])
                if jCfg['nodisk']:
                    binList.append(wlutil.noDiskPath(jCfg['bin']))

            if 'img' in jCfg and buildImg and not jCfg['img-hardcoded']:
                imgList.append(jCfg['img'])

    doitHandle = doit.doit_cmd.DoitMain(taskLoader)

    # The order isn't critical here, we should have defined the dependencies correctly in loader
    return doitHandle.run([str(p) for p in binList + imgList])


def makeInitramfs(srcs, cpioDir, includeDevNodes=False):
    """Generate a cpio archive containing each of the sources and store it in cpioDir.
    Return a path to the generated archive.
    srcs: are a list of paths to directories to include, sources will be
          applied in-order (potentially overwriting duplicate files).
    cpioDir: Scratch directory to produce outputs in
    includeDevNodes: If true, will include '/dev/console' and '/dev/tty' special files."""

    # Generate individual cpios for each source
    cpios = []
    for src in srcs:
        dst = cpioDir / (src.name + '.cpio')
        with contextlib.suppress(FileNotFoundError):
            os.remove(dst)
        wlutil.toCpio(src, dst)
        cpios.append(dst)

    if includeDevNodes:
        cpios.append(wlutil.getOpt('initramfs-dir') / 'devNodes.cpio')

    # Generate final cpio
    finalPath = cpioDir / 'initramfs.cpio'
    with contextlib.suppress(FileNotFoundError):
        os.remove(finalPath)
    with open(finalPath, 'wb') as finalF:
        for cpio in cpios:
            with open(cpio, 'rb') as srcF:
                shutil.copyfileobj(srcF, finalF)

    return finalPath


def generateKConfig(kfrags, linuxSrc, linuxBuild):
    """Generate the final .config in linuxBuild from the provided kernel fragments."""
    linuxBuild.mkdir(parents=True, exist_ok=True)
    linuxCfg = linuxBuild / '.config'
    defCfg = wlutil.getOpt('gen-dir') / 'defconfig'

    # Create a defconfig to use as reference
    wlutil.run(['make', 'O=' + str(linuxBuild)] + wlutil.getOpt('linux-make-args') + ['defconfig'], cwd=linuxSrc)
    shutil.copy(linuxCfg, defCfg)

    # Create a config from the user fragments
    kconfigEnv = os.environ.copy()
    kconfigEnv['ARCH'] = 'riscv'
    kconfigEnv['CROSS_COMPILE'] = 'riscv64-unknown-linux-gnu-'
    wlutil.run([linuxSrc / 'scripts/kconfig/merge_config.sh', '-O', str(linuxBuild), str(defCfg)] +
               list(map(str, kfrags)), env=kconfigEnv, cwd=linuxSrc)


def makeInitramfsKfrag(src, dst):
    with open(dst, 'w') as f:
        f.write("CONFIG_BLK_DEV_INITRD=y\n")
        f.write('CONFIG_INITRAMFS_SOURCE="' + str(src) + '"\n')


def makeModules(cfg):
    """Build all the kernel modules for this config. The compiled kmods will be
    put in the appropriate location in the initramfs staging area."""

    linCfg = cfg['linux']
    drivers = []

    # Prepare the linux source with the proper config
    generateKConfig(linCfg['config'], linCfg['source'], linCfg['build-dir'])
    cfg['out-dir'].mkdir(parents=True, exist_ok=True)
    shutil.copy(linCfg['build-dir'] / '.config', cfg['out-dir'] / 'linux_module_config')

    # Build modules (if they exist)
    if ('modules' in linCfg) and (len(linCfg['modules']) != 0):
        # Prepare the linux source for building external modules
        wlutil.run(["make", 'O=' + str(linCfg['build-dir'])] + wlutil.getOpt('linux-make-args') +
                   ["modules_prepare", '-j' + str(wlutil.getOpt('jlevel'))],
                   cwd=linCfg['source'])

        # MODPOST errors are warnings, since we built the extmods without building the kernel first
        makeCmd = "make KBUILD_MODPOST_WARN=1 LINUXSRC=" + str(linCfg['source']) + \
                  " LINUXBUILD=" + str(linCfg['build-dir'])

        for driverDir in linCfg['modules'].values():
            wlutil.checkSubmodule(driverDir)

            # Drivers don't seem to detect changes in the kernel
            wlutil.run(makeCmd + " clean", cwd=driverDir, shell=True)
            wlutil.run(makeCmd, cwd=driverDir, shell=True)
            drivers.extend(list(driverDir.glob("*.ko")))

    kernelVersion = sp.run(["make", '-s', 'O=' + str(linCfg['build-dir']), "ARCH=riscv", "kernelrelease"], cwd=linCfg['source'], stdout=sp.PIPE, universal_newlines=True).stdout.strip()
    driverDir = wlutil.getOpt('initramfs-dir') / "drivers" / "lib" / "modules" / kernelVersion

    # Always start from a clean slate
    try:
        shutil.rmtree(driverDir.parent)
    except FileNotFoundError:
        pass
    driverDir.mkdir(parents=True)

    # Copy in our new drivers
    for driverPath in drivers:
        shutil.copy(driverPath, driverDir)

    # Setup the dependency file needed by modprobe to load the drivers
    wlutil.run(['depmod', '-b', str(wlutil.getOpt('initramfs-dir') / "drivers"), kernelVersion])


def makeOpenSBI(config, nodisk=False):
    payload = config['linux']['build-dir'] / 'arch' / 'riscv' / 'boot' / 'Image'
    size = payload.stat().st_size

    # Sometimes static variables can exceed the size of the flat image
    # Look in the vmlinux ELF for the max address, and use that if its greater
    vmlinux = config['linux']['build-dir'] / 'vmlinux'
    # don't use wlutil.run, since we need to process the stdout
    proc = sp.Popen(['readelf', '--segments', '--wide', vmlinux], stdout=sp.PIPE, universal_newlines=True)
    proc.wait()
    for line in iter(proc.stdout.readline, ''):
        line = line.strip()
        if "LOAD" in line:
            cols = line.split()
            base = int(cols[3], 16)
            memsize = int(cols[5], 16)
            if base + memsize > size:
                size = base + memsize

    # Align to next MiB
    payloadSize = ((size + 0xfffff) // 0x100000) * 0x100000
    makeArgsOpts = ['PLATFORM=generic',
                    'FW_PAYLOAD_PATH=' + str(payload),
                    'FW_PAYLOAD_FDT_ADDR=0x$(shell printf "%X" '
                    '$$(( $(FW_TEXT_START) + $(FW_PAYLOAD_OFFSET) + ' +
                    hex(payloadSize) + ' )))']

    args = wlutil.getOpt('linux-make-args') + makeArgsOpts

    if 'opensbi-build-args' in config['firmware']:
        args += config['firmware']['opensbi-build-args']

    wlutil.run(['make', 'O=' + str(config['firmware']['build-dir'])] + args,
               cwd=config['firmware']['source'])

    return config['firmware']['build-dir'] / 'platform' / 'generic' / 'firmware' / 'fw_payload.elf'


def makeBin(config, nodisk=False):
    """Build the binary specified in 'config'.

    This is called as a doit task (see buildDepGraph() and addDep())
    """
    if config['use-parent-bin'] and not nodisk:
        config['bin'].parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(config['base-bin'], config['bin'])
        if 'dwarf' in config:
            config['dwarf'].parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(config['base-dwarf'], config['dwarf'])
        return True

    # We assume that if you're not building linux, then the image is pre-built (e.g. during host-init)
    if 'linux' in config:
        initramfsIncludes = []

        try:
            prepareBuildrootSources(config)
            makeModules(config)
        except BuildrootSourceError as err:
            return doit.exceptions.TaskFailed(err)

        initramfsIncludes.append(wlutil.getOpt('initramfs-dir') / 'drivers')
        config['out-dir'].mkdir(parents=True, exist_ok=True)
        cpioDir = config['out-dir']
        cpioDir = pathlib.Path(cpioDir)
        initramfsPath = ""
        if nodisk:
            initramfsIncludes += [wlutil.getOpt('initramfs-dir') / "nodisk"]
            with wlutil.mountImg(config['img'], wlutil.getOpt('mount-dir')):
                initramfsIncludes = [wlutil.getOpt('mount-dir')] + initramfsIncludes
                # This must be done while in the mountImg context
                initramfsPath = makeInitramfs(initramfsIncludes, cpioDir, includeDevNodes=True)
        else:
            initramfsIncludes += [wlutil.getOpt('initramfs-dir') / "disk"]
            initramfsPath = makeInitramfs(initramfsIncludes, cpioDir, includeDevNodes=True)

        makeInitramfsKfrag(initramfsPath, cpioDir / "initramfs.kfrag")
        generateKConfig(config['linux']['config'] + [cpioDir / "initramfs.kfrag"],
                        config['linux']['source'], config['linux']['build-dir'])
        wlutil.run(['make', 'O=' + str(config['linux']['build-dir'])] + wlutil.getOpt('linux-make-args') +
                   ['vmlinux', 'Image', '-j' + str(wlutil.getOpt('jlevel'))], cwd=config['linux']['source'])
        # Preserve the exact Buildroot-managed configuration alongside the workload.
        shutil.copy(config['linux']['build-dir'] / '.config', config['out-dir'] / 'linux_config')
        shutil.copy(_buildroot_busybox_source() / '.config', config['out-dir'] / 'busybox_config')

        fw = makeOpenSBI(config, nodisk)

        config['bin'].parent.mkdir(parents=True, exist_ok=True)
        config['dwarf'].parent.mkdir(parents=True, exist_ok=True)
        if nodisk:
            shutil.copy(fw, wlutil.noDiskPath(config['bin']))
            shutil.copy(config['linux']['build-dir'] / 'vmlinux', wlutil.noDiskPath(config['dwarf']))
        else:
            shutil.copy(fw, config['bin'])
            shutil.copy(config['linux']['build-dir'] / 'vmlinux', config['dwarf'])

    return True


def makeImage(config):
    log = logging.getLogger()

    # Remove old image so that you re-apply the overlay/files/etc
    with contextlib.suppress(FileNotFoundError):
        os.remove(config['img'])

    # Create new image from a copy of the base
    if 'base-img' in config:
        config['img'].parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(config['base-img'], config['img'])

    # Resize if needed
    if config['img-sz'] != 0:
        wlutil.resizeFS(config['img'], config['img-sz'])

    if 'overlay' in config:
        log.debug("Applying overlay: " + str(config['overlay']))
        wlutil.applyOverlay(config['img'], config['overlay'])

    if 'files' in config:
        log.debug("Applying file list: " + str(config['files']))
        wlutil.copyImgFiles(config['img'], config['files'], 'in')

    if 'guest-init' in config:
        log.debug("Applying init script: " + str(config['guest-init'].path))
        if not config['guest-init'].path.exists():
            raise ValueError("Init script " + str(config['guest-init'].path) + " not found.")

        # Apply and run the init script
        init_overlay = config['builder'].generateBootScriptOverlay(
            str(config['guest-init'].path), config['guest-init'].args)
        wlutil.applyOverlay(config['img'], init_overlay)
        wlutil.run(wllaunch.getQemuCmd(config), shell=True, level=logging.DEBUG)

        # Clear the init script
        run_overlay = config['builder'].generateBootScriptOverlay(None, None)
        wlutil.applyOverlay(config['img'], run_overlay)

    if 'runSpec' in config:
        spec = config['runSpec']
        if spec.command is not None:
            log.debug("Applying run command: " + str(spec.command))
            scriptPath = wlutil.genRunScript(spec.command)
        else:
            log.debug("Applying run script: " + str(spec.path))
            scriptPath = spec.path

        if not scriptPath.exists():
            raise ValueError("Run script " + str(scriptPath) + " not found.")

        run_overlay = config['builder'].generateBootScriptOverlay(scriptPath, spec.args)
        wlutil.applyOverlay(config['img'], run_overlay)

    # Tighten the image size if requested
    if config['img-sz'] == 0:
        wlutil.resizeFS(config['img'], 0)
