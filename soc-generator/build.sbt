import Tests._

val chisel6Version = "6.7.0"
val chisel7Version = "7.13.0"
val chiselTestVersion = "6.0.0"
val scalaVersionFromChisel = if (sys.env.contains("USE_CHISEL7")) "2.13.18" else "2.13.16"

val chisel3Version = "3.6.1"

// This gives us a nicer handle to the root project instead of using the
// implicit one
lazy val chipyardRoot = Project("chipyardRoot", file("."))
val chipyardRootDir = file(".").getCanonicalFile

// keep chisel/firrtl specific class files, rename other conflicts
val chiselFirrtlMergeStrategy = CustomMergeStrategy.rename { dep =>
  import sbtassembly.Assembly.{Project, Library}
  val nm = dep match {
    case p: Project => p.name
    case l: Library => l.moduleCoord.name
  }
  if (Seq("firrtl", "chisel3", "chisel").contains(nm.split("_")(0))) { // split by _ to avoid checking on major/minor version
    dep.target
  } else {
    "renamed/" + dep.target
  }
}

lazy val commonSettings = Seq(
  organization := "edu.berkeley.cs",
  version := "1.6",
  scalaVersion := scalaVersionFromChisel,
  assembly / test := {},
  assembly / assemblyMergeStrategy := {
    case PathList("chisel3", "stage", xs @ _*) => chiselFirrtlMergeStrategy
    case PathList("chisel", "stage", xs @ _*) => chiselFirrtlMergeStrategy
    case PathList("firrtl", "stage", xs @ _*) => chiselFirrtlMergeStrategy
    case PathList("META-INF", _*) => MergeStrategy.discard
    // should be safe in JDK11: https://stackoverflow.com/questions/54834125/sbt-assembly-deduplicate-module-info-class
    case x if x.endsWith("module-info.class") => MergeStrategy.discard
    case x =>
      val oldStrategy = (assembly / assemblyMergeStrategy).value
      oldStrategy(x)
  },
  scalacOptions ++= Seq(
    "-deprecation",
    "-unchecked",
    "-Ytasty-reader",
    "-Ymacro-annotations"), // fix hierarchy API
  unmanagedBase := (chipyardRoot / unmanagedBase).value,
  allDependencies := {
    // drop specific maven dependencies in subprojects in favor of Chipyard's version
    val dropDeps = Seq(("edu.berkeley.cs", "rocketchip"))
    allDependencies.value.filterNot { dep =>
      dropDeps.contains((dep.organization, dep.name))
    }
  },
  libraryDependencies += "com.lihaoyi" %% "sourcecode" % "0.3.1",
  libraryDependencies += "org.scala-lang" % "scala-reflect" % scalaVersion.value,

  exportJars := true,
  resolvers ++= Seq(
    Resolver.sonatypeRepo("snapshots"),
    Resolver.sonatypeRepo("releases"),
    Resolver.mavenLocal))

val rocketChipDir = file("generator/rocket-chip")

def projectBase(name: String, dir: File): File = {
  val canonicalDir = dir.getCanonicalFile.toPath
  if (canonicalDir.startsWith(chipyardRootDir.toPath)) dir
  else file(s".sbt-external/${name.replaceAll("[^A-Za-z0-9_.-]", "_")}")
}

def projectFromDir(name: String, dir: File): Project = {
  Project(id = name, base = projectBase(name, dir))
    .settings(
      sourceDirectory := dir / "src",
      Compile / scalaSource := dir / "src" / "main" / "scala",
      Compile / resourceDirectory := dir / "src" / "main" / "resources"
    )
}

/**
  * It has been a struggle for us to override settings in subprojects.
  * An example would be adding a dependency to rocketchip on midas's targetutils library,
  * or replacing dsptools's maven dependency on chisel with the local chisel project.
  *
  * This function works around this by specifying the project's source root at src/ and
  * overriding scalaSource and resourceDirectory.
  */
def freshProject(name: String, dir: File): Project = {
  val sourceRoot = dir / "src"
  Project(id = name, base = projectBase(name, sourceRoot))
    .settings(
      sourceDirectory := sourceRoot,
      Compile / scalaSource := sourceRoot / "main" / "scala",
      Compile / resourceDirectory := sourceRoot / "main" / "resources"
    )
}

// Fork each scala test for now, to work around persistent mutable state
// in Rocket-Chip based generators
def isolateAllTests(tests: Seq[TestDefinition]) = tests map { test =>
  val options = ForkOptions()
  new Group(test.name, Seq(test), SubProcess(options))
} toSeq


lazy val chisel6Settings = Seq(
  libraryDependencies ++= Seq("org.chipsalliance" %% "chisel" % chisel6Version),
  addCompilerPlugin("org.chipsalliance" % "chisel-plugin" % chisel6Version cross CrossVersion.full)
)
lazy val chisel7Settings = Seq(
  libraryDependencies ++= Seq("org.chipsalliance" %% "chisel" % chisel7Version),
  addCompilerPlugin("org.chipsalliance" % "chisel-plugin" % chisel7Version cross CrossVersion.full)
)
lazy val chisel3Settings = Seq(
  libraryDependencies ++= Seq("edu.berkeley.cs" %% "chisel3" % chisel3Version),
  addCompilerPlugin("edu.berkeley.cs" % "chisel3-plugin" % chisel3Version cross CrossVersion.full)
)

// Select Chisel 7 when USE_CHISEL7 is set in the environment; default to Chisel 6.
lazy val chiselSettings = (if (sys.env.contains("USE_CHISEL7")) chisel7Settings else chisel6Settings) ++ Seq(
  libraryDependencies ++= Seq(
    "org.apache.commons" % "commons-lang3" % "3.12.0",
    "org.apache.commons" % "commons-text" % "1.9"
  )
)

lazy val scalaTestSettings =  Seq(
  libraryDependencies ++= Seq(
    "org.scalatest" %% "scalatest" % "3.2.+" % "test"
  )
)


// Subproject definitions begin

// -- Rocket Chip --

lazy val hardfloat = {
  val useChisel7 = sys.env.contains("USE_CHISEL7")
  var hf = freshProject("hardfloat", file("generator/hardfloat/hardfloat"))
    .settings(chiselSettings)
    .settings(commonSettings)
    .settings(scalaTestSettings)
  if (!useChisel7) {
    hf = hf.dependsOn(midas_target_utils)
  }
  hf
}

lazy val rocketMacros  = (project in rocketChipDir / "macros")
  .settings(commonSettings)
  .settings(scalaTestSettings)

lazy val diplomacy = freshProject("diplomacy", file("generator/diplomacy/diplomacy"))
  .dependsOn(cde)
  .settings(commonSettings)
  .settings(chiselSettings)
  .settings(Compile / scalaSource := baseDirectory.value / "diplomacy")

lazy val rocketchip = freshProject("rocketchip", rocketChipDir)
  .dependsOn(hardfloat, rocketMacros, diplomacy, cde)
  .settings(commonSettings)
  .settings(chiselSettings)
  .settings(scalaTestSettings)
  .settings(
    libraryDependencies ++= Seq(
      "com.lihaoyi" %% "mainargs" % "0.5.0",
      // Chisel 7+ needs a more recent version of json4s to avoid linking errors, and json4s
      // migrated group ID at version 4.0.7.
      if (sys.env.contains("USE_CHISEL7")) {
        "io.github.json4s" %% "json4s-jackson" % "4.1.0"
      } else {
        "org.json4s" %% "json4s-jackson" % "4.0.5"
      },
      "org.scala-graph" %% "graph-core" % "1.13.5"
    )
  )
lazy val rocketLibDeps = (rocketchip / Keys.libraryDependencies)


// -- Chipyard-managed External Projects --

lazy val testchipip = withInitCheck(freshProject("testchipip", file("generator/testchipip")), "testchipip")
  .dependsOn(rocketchip, rocketchip_blocks)
  .settings(libraryDependencies ++= rocketLibDeps.value)
  .settings(commonSettings)

lazy val chipyard = {
  val useChisel7 = sys.env.contains("USE_CHISEL7")
  // Base chipyard project with always-on dependencies
  // Use explicit Project(...) so the project id remains 'chipyard'
  val baseProjects: Seq[ProjectReference] =
    Seq(
      testchipip, rocketchip, boom, gemmini, rocketchip_blocks, rocketchip_inclusive_cache,
    ).map(sbt.Project.projectToRef) ++
    (if (useChisel7) Seq() else Seq(sbt.Project.projectToRef(firrtl2_bridge))) ++
    (if (useChisel7) Seq() else Seq(sbt.Project.projectToRef(dsptools)))

  val baseDeps: Seq[sbt.ClasspathDep[sbt.ProjectReference]] =
    baseProjects.map(pr => sbt.ClasspathDependency(pr, None))

  val chisel7SourceExcludeSettings: Seq[Def.Setting[_]] = Seq(
    Compile / unmanagedSources := {
      val files = (Compile / unmanagedSources).value
      val root = (ThisBuild / baseDirectory).value
      val excludeList = Seq(
        // Directories or files relative to repo root
        "generator/chipyard/src/main/scala/config/SpikeConfigs.scala",
        "generator/chipyard/src/main/scala/config/ChipletConfigs.scala",
        "generator/chipyard/src/main/scala/SpikeTile.scala",
        "generator/chipyard/src/main/scala/example/dsptools"
      ) ++ (if (useChisel7) Seq(
        "generator/chipyard/src/main/scala/config/MMIOAcceleratorConfigs.scala",
        "generator/chipyard/src/main/scala/upf"
      ) else Seq.empty)
      val excludes = excludeList.distinct.map(p => (root / p).getCanonicalFile)
      val (excludeDirs, excludeFiles) = excludes.partition(_.isDirectory)
      files.filterNot { f =>
        val cf = f.getCanonicalFile
        excludeFiles.contains(cf) || excludeDirs.exists(d => cf.toPath.startsWith(d.toPath))
      }
    }
  )

  Project(id = "chipyard", base = file("generator/chipyard"))
    .dependsOn(baseDeps: _*)
    .settings(libraryDependencies ++= rocketLibDeps.value)
    .settings(
      libraryDependencies ++= Seq(
        "org.reflections" % "reflections" % "0.10.2"
      )
    )
    .settings(commonSettings)
    .settings(Compile / unmanagedSourceDirectories += {
      if (useChisel7) file("../dependencies/tools/stage-chisel7/src/main/scala")
      else file("../dependencies/tools/stage/src/main/scala")
    })
    .settings(chisel7SourceExcludeSettings: _*)
}

// Helper: fail fast if a generator project is used without its submodule initialized.
def withInitCheck(p: Project, genDirName: String): Project = {
  val checkTask = Def.task {
    val root = (ThisBuild / baseDirectory).value
    val dir = root / s"generator/$genDirName"
    val looksInitialized = (dir / ".git").exists
    if (!dir.exists || !looksInitialized) {
      sys.error(
        s"Generator '$genDirName' is not initialized at '" + dir.getAbsolutePath +
        "'. Initialize the submodule with ../init-submodules.sh.")
    }
  }
  p.settings(
    // Run the check whenever this project's code is compiled/tested/run
    Compile / compile := (Compile / compile).dependsOn(checkTask).value,
    Test / compile := (Test / compile).dependsOn(checkTask).value,
    Compile / run := (Compile / run).dependsOn(checkTask).evaluated
  )
}

lazy val tapeout = projectFromDir("tapeout", file("../dependencies/tools/tapeout/"))
  .settings(chisel3Settings) // stuck on chisel3 and SFC
  .settings(commonSettings)
  .settings(scalaVersion := "2.13.10") // stuck on chisel3 2.13.10
  .settings(libraryDependencies ++= Seq("com.typesafe.play" %% "play-json" % "2.9.2"))

lazy val fixedpoint = freshProject("fixedpoint", file("../dependencies/tools/fixedpoint"))
  .settings(chiselSettings)
  .settings(commonSettings)

lazy val dsptools = freshProject("dsptools", file("../dependencies/tools/dsptools"))
  .dependsOn(fixedpoint)
  .settings(
    chiselSettings,
    commonSettings,
    scalaTestSettings,
    libraryDependencies ++= Seq(
      "edu.berkeley.cs" %% "chiseltest" % chiselTestVersion,
      "org.typelevel" %% "spire" % "0.18.0",
      "org.scalanlp" %% "breeze" % "2.1.0",
      "junit" % "junit" % "4.13" % "test",
      "org.scalacheck" %% "scalacheck" % "1.14.3" % "test",
  ))

lazy val cde = projectFromDir("cde", file("../dependencies/tools/cde"))
  .settings(commonSettings)
  .settings(Compile / scalaSource := file("../dependencies/tools/cde/cde/src/chipsalliance/rocketchip"))

lazy val rocketchip_blocks = withInitCheck((project in file("generator/rocket-chip-blocks")), "rocket-chip-blocks")
  .dependsOn(rocketchip)
  .settings(libraryDependencies ++= rocketLibDeps.value)
  .settings(commonSettings)

lazy val rocketchip_inclusive_cache = withInitCheck((project in file("generator/rocket-chip-inclusive-cache")), "rocket-chip-inclusive-cache")
  .settings(
    commonSettings,
    Compile / scalaSource := baseDirectory.value / "design/craft")
  .dependsOn(rocketchip)
  .settings(libraryDependencies ++= rocketLibDeps.value)

lazy val boom = withInitCheck(freshProject("boom", file("generator/boom")), "boom")
  .dependsOn(rocketchip)
  .settings(libraryDependencies ++= rocketLibDeps.value)
  .settings(commonSettings)

lazy val gemmini = withInitCheck(freshProject("gemmini", file("generator/gemmini")), "gemmini")
  .dependsOn(rocketchip)
  .settings(libraryDependencies ++= rocketLibDeps.value)
  .settings(commonSettings)

lazy val fpga_shells = projectFromDir("fpga_shells", file("../dependencies/fpga/fpga-shells"))
  .dependsOn(rocketchip, rocketchip_blocks)
  .settings(libraryDependencies ++= rocketLibDeps.value)
  .settings(commonSettings)

lazy val chipyard_fpga = projectFromDir("chipyard_fpga", file("../dependencies/fpga"))
  .dependsOn(chipyard, fpga_shells)
  .settings(commonSettings)

// Components of FireSim

lazy val firrtl2 = freshProject("firrtl2", file("../dependencies/tools/firrtl2"))
  .enablePlugins(BuildInfoPlugin)
  .enablePlugins(Antlr4Plugin)
  .settings(commonSettings)
  .settings(
    sourceDirectory := file("../dependencies/tools/firrtl2/src"),
    scalacOptions ++= Seq(
      "-language:reflectiveCalls",
      "-language:existentials",
      "-language:implicitConversions"),
    libraryDependencies ++= Seq(
      "org.scalatest" %% "scalatest" % "3.2.14" % "test",
      "org.scalatestplus" %% "scalacheck-1-15" % "3.2.11.0" % "test",
      "com.github.scopt" %% "scopt" % "4.1.0",
      "org.json4s" %% "json4s-native" % "4.1.0-M4",
      "org.apache.commons" % "commons-text" % "1.10.0",
      "com.lihaoyi" %% "os-lib" % "0.8.1",
      "org.scala-lang.modules" %% "scala-parallel-collections" % "1.0.4"),
    Antlr4 / antlr4GenVisitor := true,
    Antlr4 / antlr4GenListener := true,
    Antlr4 / antlr4PackageName := Option("firrtl2.antlr"),
    Antlr4 / antlr4Version := "4.9.3",
    Antlr4 / javaSource := (Compile / sourceManaged).value,
    buildInfoPackage := "firrtl2",
    buildInfoUsePackageAsPath := true,
    buildInfoKeys := Seq[BuildInfoKey](buildInfoPackage, version, scalaVersion, sbtVersion)
  )

lazy val firrtl2_bridge = freshProject("firrtl2_bridge", file("../dependencies/tools/firrtl2/bridge"))
  .dependsOn(firrtl2)
  .settings(commonSettings)
  .settings(chiselSettings)

lazy val firesimDir = file("sims/firesim")

// Contains annotations & firrtl passes you may wish to use in rocket-chip without
// introducing a circular dependency between RC and MIDAS.
// Minimal in scope (should only depend on Chisel/Firrtl that is
// cross-compilable between FireSim Chisel 3.* and Chipyard Chisel 6+)
lazy val midas_target_utils = (project in firesimDir / "sim/midas/targetutils")
  .settings(commonSettings)
  .settings(chiselSettings)

// Provides API for bridges to be created in the target.
// Includes target-side of FireSim-provided bridges and their interfaces that are shared
// between FireSim and the target. Minimal in scope (should only depend on Chisel/Firrtl that is
// cross-compilable between FireSim Chisel 3.* and Chipyard Chisel 6+)
lazy val firesim_lib = (project in firesimDir / "sim/firesim-lib")
  .dependsOn(midas_target_utils)
  .settings(commonSettings)
  .settings(chiselSettings)
  .settings(scalaTestSettings)

// Interfaces for target-specific bridges shared with FireSim.
// Minimal in scope (should only depend on Chisel/Firrtl).
// This is copied to FireSim's GoldenGate compiler.
lazy val firechip_bridgeinterfaces = (project in file("generator/firechip/bridgeinterfaces"))
  .settings(
    chiselSettings,
    commonSettings,
  )

// Target-side bridge definitions, CC files, etc used for FireSim.
// This only compiled with Chipyard.
lazy val firechip_bridgestubs = (project in file("generator/firechip/bridgestubs"))
  .dependsOn(chipyard, firesim_lib % "compile->compile;test->test", firechip_bridgeinterfaces)
  .settings(
    chiselSettings,
    commonSettings,
    Test / testGrouping := isolateAllTests( (Test / definedTests).value ),
    Test / testOptions += Tests.Argument("-oF")
  )
  .settings(scalaTestSettings)

// FireSim top-level project that includes the FireSim harness, CC files, etc needed for FireSim.
lazy val firechip = (project in file("generator/firechip/chip"))
  .dependsOn(chipyard, firesim_lib % "compile->compile;test->test", firechip_bridgestubs, firechip_bridgeinterfaces)
  .settings(
    chiselSettings,
    commonSettings,
    Test / testGrouping := isolateAllTests( (Test / definedTests).value ),
    Test / testOptions += Tests.Argument("-oF")
  )
  .settings(scalaTestSettings)
