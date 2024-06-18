import fs from "fs";
import path from "path";

function updateVersionInPackageJson(
  dir: string,
  version: string,
  packagesInWorkspace: string[]
) {
  const packageJsonPath = path.join(dir, "package.json");
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));

  packageJson.version = version;

  if (packageJson.dependencies) {
    packageJson.dependencies = Object.fromEntries(
      Object.entries(packageJson.dependencies).map((entry) => {
        const [k, v] = entry as [string, string];
        return [k, packagesInWorkspace.includes(k) ? `${version}` : v];
      })
    );
  }

  fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2));
}

function getVersion(dir: string): string {
  const versionFilePath = path.join(dir, "sdk/VERSION");
  const v = fs.readFileSync(versionFilePath);
  return v.toString().replace("\n", "");
}

function getPackageName(dir: string): string {
  const packageJsonPath = path.join(dir, "package.json");
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
  return packageJson.name;
}

type Workspace = {
  // workspace name
  name: string;
  // path to workspace
  path: string;
  // package name
  package: string;
};

function updateVersionsInWorkspaces(dir: string) {
  const version = getVersion(dir);

  const packageJsonPath = path.join(dir, "package.json");
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));

  const workspaces = packageJson.workspaces.map((workspaceName: string) => {
    const workspaceDir = path.join(dir, workspaceName);
    return {
      name: workspaceName,
      path: workspaceDir,
      package: getPackageName(workspaceDir),
    } as Workspace;
  });

  const workspacePackages = workspaces.map((ws: Workspace) => ws.package);

  // Root update
  updateVersionInPackageJson(dir, version, workspacePackages);

  // Workspaces update
  workspaces.forEach((ws: Workspace) => {
    updateVersionInPackageJson(ws.path, version, workspacePackages);
  });
}

updateVersionsInWorkspaces(path.resolve("."));
