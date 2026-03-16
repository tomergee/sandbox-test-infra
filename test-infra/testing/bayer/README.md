Bayer test spec
===============

This is a test spec that mimics bayer architecture. It will be used for GKE scalability tests.

The spec is based on: https://docs.google.com/document/d/1nljlA98jCaxfBAUIe9K7E7h3FU5hduBzr7uqqCx1gHw/edit?ts=5de50f49

The test exercises Preemptible Nodes and ClusterAutoscaler. Currently it starts from 600 nodes (due to b/147126440) then scales up to 15k and back to 600 using the following intermittent steps: `600 -> 6k -> 10k -> 15k -> 10k -> 6k -> 600`

The test results can be found in b/147282017

How to run it?
--------------

Modify the input parameters (e.g. `PROJECT` or `VERSION`) and run the `run.sh` script.
