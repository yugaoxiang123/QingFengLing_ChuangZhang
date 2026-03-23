#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
APK文件信息生成工具
自动计算APK文件的大小、MD5和SHA256值，用于更新配置
"""

import os
import sys
import hashlib
import argparse
from pathlib import Path
from datetime import datetime


def calculate_file_hash(file_path, hash_type='md5'):
    """计算文件的哈希值"""
    if hash_type.lower() == 'md5':
        hash_obj = hashlib.md5()
    elif hash_type.lower() == 'sha256':
        hash_obj = hashlib.sha256()
    else:
        raise ValueError(f"不支持的哈希类型: {hash_type}")
    
    try:
        with open(file_path, 'rb') as f:
            # 分块读取文件，避免大文件占用过多内存
            for chunk in iter(lambda: f.read(4096), b""):
                hash_obj.update(chunk)
        return hash_obj.hexdigest()
    except FileNotFoundError:
        print(f"错误: 文件不存在 - {file_path}")
        return None
    except Exception as e:
        print(f"错误: 计算哈希值失败 - {e}")
        return None


def get_file_size(file_path):
    """获取文件大小（字节）"""
    try:
        return os.path.getsize(file_path)
    except FileNotFoundError:
        print(f"错误: 文件不存在 - {file_path}")
        return None
    except Exception as e:
        print(f"错误: 获取文件大小失败 - {e}")
        return None


def generate_file_info(apk_path):
    """生成APK文件信息"""
    print(f"正在分析APK文件: {apk_path}")
    
    # 检查文件是否存在
    if not os.path.exists(apk_path):
        print(f"错误: APK文件不存在 - {apk_path}")
        return None
    
    # 获取文件大小
    file_size = get_file_size(apk_path)
    if file_size is None:
        return None
    
    print(f"文件大小: {file_size:,} 字节 ({file_size / 1024 / 1024:.2f} MB)")
    
    # 计算MD5
    print("正在计算MD5...")
    md5_hash = calculate_file_hash(apk_path, 'md5')
    if md5_hash is None:
        return None
    
    # 计算SHA256
    print("正在计算SHA256...")
    sha256_hash = calculate_file_hash(apk_path, 'sha256')
    if sha256_hash is None:
        return None
    
    return {
        'size': file_size,
        'md5': md5_hash,
        'sha256': sha256_hash
    }


def format_yaml_output(file_info):
    """格式化YAML输出"""
    yaml_content = f"""  file_info:
    size: {file_info['size']}  # 文件大小（字节）
    md5: "{file_info['md5']}"  # MD5校验值
    sha256: "{file_info['sha256']}"  # SHA256校验值"""
    return yaml_content


def update_yaml_file(yaml_path, file_info, update_build_date=True):
    """更新YAML文件中的file_info部分和build_date"""
    try:
        # 读取现有的YAML文件
        with open(yaml_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        # 获取当前日期
        current_date = datetime.now().strftime("%Y-%m-%d")
        
        # 查找file_info部分并替换，同时更新build_date
        new_lines = []
        in_file_info = False
        file_info_found = False
        build_date_updated = False
        
        for line in lines:
            # 更新build_date字段
            if update_build_date and 'build_date:' in line and not build_date_updated:
                indent = len(line) - len(line.lstrip())
                new_lines.append(' ' * indent + f'build_date: "{current_date}"\n')
                build_date_updated = True
                print(f"[OK] 已更新构建日期: {current_date}")
                continue
            
            # 处理file_info部分
            if line.strip() == 'file_info:':
                file_info_found = True
                in_file_info = True
                new_lines.append(line)
                # 添加新的file_info内容
                new_lines.append(f"    size: {file_info['size']}  # 文件大小（字节）\n")
                new_lines.append(f"    md5: \"{file_info['md5']}\"  # MD5校验值\n")
                new_lines.append(f"    sha256: \"{file_info['sha256']}\"  # SHA256校验值\n")
                continue
            
            # 跳过原有的file_info内容
            if in_file_info:
                if line.startswith('    ') and ':' in line:
                    continue  # 跳过file_info下的字段
                else:
                    in_file_info = False
            
            new_lines.append(line)
        
        # 如果没有找到file_info部分，在文件末尾添加
        if not file_info_found:
            if not new_lines[-1].endswith('\n'):
                new_lines.append('\n')
            new_lines.append('\n  # 文件信息\n')
            new_lines.append('  file_info:\n')
            new_lines.append(f"    size: {file_info['size']}  # 文件大小（字节）\n")
            new_lines.append(f"    md5: \"{file_info['md5']}\"  # MD5校验值\n")
            new_lines.append(f"    sha256: \"{file_info['sha256']}\"  # SHA256校验值\n")
        
        # 写回文件
        with open(yaml_path, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
        
        print(f"[OK] YAML文件已更新: {yaml_path}")
        return True
        
    except Exception as e:
        print(f"错误: 更新YAML文件失败 - {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description='生成APK文件信息用于自动更新配置')
    parser.add_argument('apk_path', help='APK文件路径')
    parser.add_argument('--yaml', help='要更新的YAML文件路径（可选）')
    parser.add_argument('--output', '-o', help='输出结果到文件（可选）')
    parser.add_argument('--no-date', action='store_true', help='不更新build_date字段')
    parser.add_argument('--md5-only', action='store_true', help='仅输出MD5值（用于脚本调用）')
    
    args = parser.parse_args()
    
    # 如果只需要MD5，直接计算并输出
    if args.md5_only:
        md5_hash = calculate_file_hash(args.apk_path, 'md5')
        if md5_hash is None:
            sys.exit(1)
        print(md5_hash)
        sys.exit(0)
    
    # 生成文件信息
    file_info = generate_file_info(args.apk_path)
    if file_info is None:
        sys.exit(1)
    
    # 打印结果
    print("\n" + "="*50)
    print("APK文件信息:")
    print("="*50)
    print(f"文件路径: {args.apk_path}")
    print(f"文件大小: {file_info['size']:,} 字节")
    print(f"MD5:      {file_info['md5']}")
    print(f"SHA256:   {file_info['sha256']}")
    print("="*50)
    
    # 生成YAML格式输出
    yaml_output = format_yaml_output(file_info)
    print("\nYAML格式输出:")
    print("-" * 30)
    print(yaml_output)
    print("-" * 30)
    
    # 如果指定了输出文件，保存结果
    if args.output:
        try:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(yaml_output)
            print(f"\n[OK] 结果已保存到: {args.output}")
        except Exception as e:
            print(f"\n[ERROR] 保存文件失败: {e}")
    
    # 如果指定了YAML文件，直接更新
    if args.yaml:
        update_build_date = not args.no_date
        if update_yaml_file(args.yaml, file_info, update_build_date):
            print(f"[OK] 已自动更新YAML文件")
        else:
            print(f"[ERROR] 更新YAML文件失败")


if __name__ == '__main__':
    main() 