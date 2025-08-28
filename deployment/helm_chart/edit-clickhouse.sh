#!/bin/bash
# 备份原始文件
#cp opik/templates/deployment.yaml opik/templates/deployment.yaml.original

# 直接修改镜像路径构建逻辑，去掉registry前缀
sed -i.bak 's|image: "{{ $.Values.registry }}/{{ $value.image.repository }}:{{ $value.image.tag }}"|image: "{{ $value.image.repository }}:{{ $value.image.tag }}"|g' opik/templates/deployment.yaml

echo "✅ Chart模板已修改，现在将直接使用repository值，无需添加registry前缀"
echo "检查修改结果："
grep -n 'image: "' opik/templates/deployment.yaml