#!/bin/bash

# Branches que não serão apagadas
protected_branches=("main" "master" "production" "staging")

# Pega a branch atual para evitar deletá-la
current_branch=$(git symbolic-ref --short HEAD)

# Lista todas as branches locais
branches=$(git for-each-ref --format='%(refname:short)' refs/heads/)

# Lista de branches remotas conhecidas localmente (origin/<branch>)
remote_branches=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin/)

current_wt_path=$(git rev-parse --show-toplevel)

has_remote_branch() {
  local branch="$1"
  local remote
  for remote in $remote_branches; do
    if [[ "$remote" == "origin/$branch" ]]; then
      return 0
    fi
  done
  return 1
}

# Retorna o caminho do worktree associado à branch (vazio se não houver)
worktree_path_for_branch() {
  local branch="$1"
  git worktree list --porcelain | awk -v target="branch refs/heads/$branch" '
    /^worktree / { wt = substr($0, index($0, " ") + 1) }
    $0 == target { print wt; exit }
  '
}

for branch in $branches; do
  skip=false

  # Verifica se a branch está na lista de protegidas
  for protected in "${protected_branches[@]}"; do
    if [[ "$branch" == "$protected" ]]; then
      skip=true
      break
    fi
  done

  # Não apaga a branch atual ou protegidas
  if [[ "$skip" = true || "$branch" == "$current_branch" ]]; then
    continue
  fi

  # Não apaga branches que ainda possuem branch remota associada
  if has_remote_branch "$branch"; then
    echo "Mantendo branch: $branch (possui branch remota origin/$branch)"
    continue
  fi

  # Se a branch estiver associada a um worktree, remove o worktree primeiro
  wt_path=$(worktree_path_for_branch "$branch")
  if [[ -n "$wt_path" ]]; then
    if [[ "$wt_path" == "$current_wt_path" ]]; then
      echo "Mantendo branch: $branch (checked out no worktree atual: $wt_path)"
      continue
    fi

    echo "Removendo worktree: $wt_path (branch: $branch)"
    wt_error_file=$(mktemp)
    if ! git worktree remove "$wt_path" 2>"$wt_error_file"; then
      echo "Mantendo branch: $branch (worktree possui alterações não commitadas: $wt_path)"
      cat "$wt_error_file"
      rm -f "$wt_error_file"
      continue
    fi
    rm -f "$wt_error_file"
  fi

  echo "Apagando branch: $branch"
  git branch -D "$branch"
done
