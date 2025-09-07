# Claude Code Instructions

* to test your changes, cd into the directory you want to test and run 'go test'
* The directory ~/aiplayground is dedicated for you to do anything, you have full permission to edit files and directories in this directory.
* Keep documentation short and blunt.
* Don't add "demo", "verify" kind of script unless I ask you to. Do add unit tests though.
* Make sure there is no compile error before finish the task.
* If .go files are updated, make sure use go fmt to format it, run go fmt on the file, not on the directory to avoid unnecessary changes.
* For Golang project, run go test in that directory to make sure you are not breaking anything.
* For Go unit test, if it's a Ginkgo style, First run `go test` in that directory to get failed test cases. For each failed test case, change it to fit to focus on that particular test case and fix it. 
* If editing the aks rp repo https://msazure.visualstudio.com/DefaultCollection/CloudNativeCompute/_git/aks-rp , after the task is done, run `./hack/aksbuilder.sh tidy -w <workspace_path>` (replaces `go mod tidy`) to tidy dependencies, e.g. `./hack/aksbuilder.sh tidy -w resourceprovider/server`.

## Golang Specific Instructions

* When writing golang code, follow the Effective Go recommendations: <https://go.dev/doc/effective_go>
* Do not use %v or %+v, we found many security issue caused by using %v %+v, so we banned it.
