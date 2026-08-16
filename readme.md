# TCF FRAPPE DEVELOPMENT

Container orchestration and bootstrap scripts for the TCF Frappe Development environment.

## Quickstart

This assumes a valid ssh configuration is already set up for git.

    git clone https://github.com/FabioTessaro/tcf_frappe_dev.git frappe-dev
    cd frappe-dev
    cp .env.example .env
    nano .env
    ./install.sh
    # Open this folder remotely via ssh in VS Code -> "Reopen in Container"

First container creation runs bootstrap/setup-bench.sh automatically, which
initializes bench, fetches erpnext/hrms and the apps listed in TCF_APPS,
and creates tcf.local with developer_mode enabled.

## Apps

App code is NOT stored in this repo. TCF_APPS in .env controls which of
tcf_hr, tcf_erp, tcf_plm, tcf_qms, tcf_web get cloned and installed on bootstrap.
