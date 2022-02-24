#/bin/bash
VERSION=$1
MAJOR_VERSION="v1.x"
git fetch
git checkout main
git pull
echo "Merging to ${MAJOR_VERSION}"
git checkout $MAJOR_VERSION
git pull
if git merge --ff-only origin/main; then
  git push
  git tag -a $VERSION -m "Release ${VERSION}"
  git push origin $VERSION
  echo "Creating Release"
  gh release create $VERSION --title "Release $VERSION" --notes ""
else
  echo "RELEASE FAILED! Could not fast-forward release to $MAJOR_VERSION"
fi
git checkout main
