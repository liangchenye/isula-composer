package main

import (
	"gopkg.in/yaml.v2"
)

// BaseRootfs represents the basic os pkgs
type BaseRootfs struct {
	Kernel struct {
		Cmdline string
	}
	AddPackages []string
	RmPackages  []string
	Files       struct {
		Add    [][]string
		Remove []string
	}
}

// AddonRootfs represents the additional os pkgs
type AddonRootfs struct {
	InitRootfs struct {
		File string
	}
	Kernel struct {
		Cmdline string
	}
	Features      []string
	AddPackages   []string
	RmPackages    []string
	SysContainers []struct {
		Name  string
		Image string
	}
	AppContainers []struct {
		Name  string
		Image string
	}
	Files struct {
		Add    [][]string
		Remove []string
	}
	Outputs []string
}

func convert(i interface{}) interface{} {
	switch x := i.(type) {
	case map[interface{}]interface{}:
		m2 := map[string]interface{}{}
		for k, v := range x {
			m2[k.(string)] = convert(v)
		}
		return m2
	case []interface{}:
		for i, v := range x {
			x[i] = convert(v)
		}
	}
	return i
}

// NewAddonConfig parses a addon config Files
func NewAddonConfig(config []byte) (AddonRootfs, error) {
	m := AddonRootfs{}

	// Parse yaml
	err := yaml.Unmarshal(config, &m)
	if err != nil {
		return m, err
	}

	return m, nil
}

// NewBaseConfig parses a base config file
func NewBaseConfig(config []byte) (BaseRootfs, error) {
	m := BaseRootfs{}

	// Parse yaml
	err := yaml.Unmarshal(config, &m)
	if err != nil {
		return m, err
	}

	return m, nil
}
