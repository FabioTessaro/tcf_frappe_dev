# tcf_frappe_dev

Container orchestration and bootstrap scripts for the TCF Frappe development environment.

## Quickstart

    git clone git@github.com:FabioTessaro/tcf_frappe_dev.git frappe-dev
    cd frappe-dev
    cp .env.example .env   # fill in real passwords and app list
    ./install.sh
    # Open this folder in VS Code -> "Reopen in Container"

First container creation runs bootstrap/setup-bench.sh automatically, which
initializes bench, fetches erpnext/hrms and the apps listed in TCF_APPS,
and creates tcf.local with developer_mode enabled.

## Apps

App code is NOT stored in this repo. TCF_APPS in .env controls which of
tcf_erp, tcf_plm, tcf_qms, tcf_web get cloned and installed on bootstrap.