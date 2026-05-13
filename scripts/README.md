# Scripts - Infinite Drive

> **Copyright (c) 2025 Deep Thought Labs**  
> Automation scripts for Infinite Drive.

## 📚 Documentation

- [README — build from source](../README.md#option-3-build-from-this-repository) (prerequisites step uses `check_build_prerequisites.sh`)
- [Official documentation](https://docs.infinitedrive.xyz/en)
- Upgrade notes: [docs/migrations/](../docs/migrations/) in this repository

## 🔍 Identifying Deep Thought Labs Scripts

All scripts developed by Deep Thought Labs have this header:

```bash
#!/bin/bash
#
# Copyright (c) 2025 Deep Thought Labs
# All rights reserved.
#
# This file is part of the Infinite Drive blockchain tooling.
```

**To find all Deep Thought Labs scripts:**

```bash
# Find all Deep Thought Labs scripts
grep -l "Deep Thought Labs" scripts/*.sh
```

## 📋 Quick Reference

Before `make install`, run the prerequisite script from the repository root when you build from source.

| Script | Purpose | Notes |
|--------|---------|--------|
| `check_build_prerequisites.sh` | Verify Docker, Go, Make, Git, and related tooling | Run from repository root: `./scripts/check_build_prerequisites.sh` |
| `infinite_health_check.sh` | Node health check | See [official documentation](https://docs.infinitedrive.xyz/en) |
