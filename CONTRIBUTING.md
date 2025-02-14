# Contributing

### License

AIPC-DEVKIT-INSTALL is licensed under the terms in [LICENSE](License.txt). By contributing to the project, you agree to the license and copyright terms therein and release your contribution under these terms.

### Sign your work

Please use the sign-off line at the end of the patch. Your signature certifies that you wrote the patch or otherwise have the right to pass it on as an open-source patch. The rules are pretty simple: if you can certify
the below (from [developercertificate.org](http://developercertificate.org/)):

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.
660 York Street, Suite 102,
San Francisco, CA 94110 USA

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

Then you just add a line to every git commit message:

    Signed-off-by: Joe Smith <joe.smith@email.com>

Use your real name (sorry, no pseudonyms or anonymous contributions.)

If you set your `user.name` and `user.email` git configs, you can sign your
commit automatically with `git commit -s`.

## Forms of contribution

### Provide Feedback

* **Report bugs / issues**
    If you experience faulty behavior, you can [create a new issue](https://github.com/intel/aipc-devkit-install/issues) in the GitHub issue tracker.
* **Propose new features / improvements**
    If you have a suggestion for improvement or idea is already well defined, you can also create a
    [Feature Request Issue](https://github.com/intel/aipc-devkit-install/issues)

In both cases, provide a detailed description, including use cases, benefits, and potential challenges. If your points are especially well aligned with the product vision, they will be included in the development roadmap.

### Contribute Code Changes

If you want to help improving choose one of the issues reported in [GitHub Issue Tracker](https://github.com/intel/aipc-devkit-install/issues) and create a Pull Request addressing it. Before creating a new PR, check if nobody is already working on it. In such a case, you may still help, having aligned with the other developer.

### Submit a PR with your changes

Follow our [Good Pull Request guidelines](#general-rules-of-a-good-pull-request). Please remember about linking your Pull Request to the issue it addresses. 

### Wait for a review

We'll make sure to review your Pull Request as soon as possible and provide you with our feedback. 

## General Rules of a Good Pull Request

* Create your own fork of the repository and use it to create PRs. Avoid creating change branches in the main repository.
* Choose a proper branch for your work and create your own branch based on it.
* Give your branches, commits, and Pull Requests meaningful names and descriptions. It helps to track changes later.
* Make your PRs small - each PR should address one issue. Remove all changes unrelated to the PR.
* For Work In Progress, use a Draft PR.

### Integration process

* Once the Pull Request is approved, validation process will be initiated.
* After validation, the changes will be available in the main branch during the release.

## Need Additional Help? Check these Articles

* [How to create a fork](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo) 

## License

By contributing, you agree that your contributions will be licensed under the terms stated in the [LICENSE](License.txt) file.