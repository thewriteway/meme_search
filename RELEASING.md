# Releasing Meme Search

Meme Search publishes two multi-platform images and a GitHub release. Version tags must use the `vX.Y.Z` format.

## Release checklist

1. Merge the intended release changes and update `VERSION` to `X.Y.Z`.
2. Record the release commit SHA and avoid merging additional commits until the images and tag are published.
3. Run both manual workflows against that same ref:
   - **Build Rails container**
   - **Build image-to-text container**
4. Confirm both workflows succeed. They publish multi-platform `latest` images with source-revision labels, SBOMs, and provenance attestations.
5. Tag the recorded commit and push the tag:

   ```sh
   git tag -a vX.Y.Z RELEASE_COMMIT_SHA -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

6. The Release workflow verifies that:
   - the tag matches `VERSION`;
   - both `latest` images were built from the tagged commit; and
   - versioned image tags can be created from those manifests.
7. Confirm the generated GitHub release and both versioned GHCR tags are visible.

If either image revision does not match the tag, the release fails before publishing. Rebuild both images from the release commit, then rerun the failed workflow.
