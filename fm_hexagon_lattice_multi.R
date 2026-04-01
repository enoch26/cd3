#' Generate hexagon lattices of different edge lengths from multiple sf layers 
#' without duplicate overlap coverage
#' 
#' Takes a list of polygonal \code{sf} objects, automatically resolves their
#' processing order by dissolved area, removes overlap already covered by
#' smaller layers, and applies \code{fm_hexagon_lattice()} to each resulting
#' non-overlapping boundary.
#'
#' This ensures that overlapped regions are applied with fm_hexagon_lattice only 
#' once across all inputs, even if the input list is supplied in any order.
#'
#' @param sf_list A non-empty list of polygonal \code{sf} objects. All layers
#'   must share the same CRS.
#' @param edge_len Numeric scalar or numeric vector of hexagon edge lengths
#'   passed to \code{fm_hexagon_lattice()}. If length 1, it is recycled to the
#'   number of layers.
#' @param clip_to Optional \code{sf} object used to clip cleaned boundaries
#'   before hexagon lattice generation. Default is \code{NULL}.
#' @param return_order Character string, either \code{"input"} or
#'   \code{"processed"}. If \code{"input"}, returned \code{cleaned} and
#'   \code{hex} lists follow the original input order. If \code{"processed"},
#'   they follow internal processing order. Default is \code{"input"}.
#' @param make_valid Logical; if \code{TRUE}, applies
#'   \code{sf::st_make_valid()} to input layers and \code{clip_to} when
#'   supplied. Default is \code{TRUE}.
#' @param drop_empty Logical; if \code{TRUE}, drops layers that become empty
#'   after overlap removal or clipping. Default is \code{TRUE}.
#' @param check_crs Logical; if \code{TRUE}, checks that all layers have the
#'   same CRS, and that \code{clip_to} matches. Default is \code{TRUE}.
#' @param verbose Logical; if \code{TRUE}, prints progress messages.
#'   Default is \code{TRUE}.
#'
#' @details
#' Let the internally sorted dissolved layers be
#' $$x_1, x_2, \dots, x_n$$,
#' ordered from smallest area to largest area.
#'
#' Cleaned boundaries are computed as:
#'
#' \deqn{x_1^{clean} = x_1}
#' \deqn{x_i^{clean} = x_i \setminus \bigcup_{j < i} x_j^{clean}, \quad i > 1}
#'
#' This guarantees that:
#' \itemize{
#'   \item overlapped regions are assigned only once;
#'   \item smaller, more specific layers are preserved ahead of larger enclosing layers;
#'   \item results do not depend on the order in which \code{sf_list} is supplied.
#' }
#'
#' @return A named list with elements:
#' \describe{
#'   \item{overlap_matrix}{Logical matrix of pairwise intersections among
#'   dissolved layers in processed order.}
#'   \item{areas}{Named numeric vector of dissolved areas in processed order.}
#'   \item{processed_names}{Character vector giving the internal processing order.}
#'   \item{cleaned}{List of cleaned non-overlapping \code{sf} boundaries.}
#'   \item{hex}{List of outputs from \code{fm_hexagon_lattice()}, one per
#'   cleaned layer.}
#'   \item{hex_combined}{Combined lattice object, or \code{NULL}.}
#' }
#'
#' @examples
#' \dontrun{
#' 
#' bnd_outer <- lapply(fm_extensions(cbind(0, 0), convex = c(3, 5)), st_as_sf)
#' bnd_inner <- lapply(fm_extensions(cbind(0, 0), convex = c(1, 1.5)), st_as_sf)
#' res <- fm_hexagon_lattice_multi(
#'   sf_list = list(
#'     bnd_outer2 = bnd_outer[[2]],
#'     bnd_inner1 = bnd_inner[[1]],
#'     bnd_outer1 = bnd_outer[[1]],
#'     bnd_inner2 = bnd_inner[[2]]
#'   ),
#'   edge_len = c(0.2, 0.4, 0.4, 0.1) 
#' )
#'
#' res$processed_names
#' res$cleaned
#' res$hex_combined
#' 
#' ggplot() + 
#' gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
#' gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
#' gg(st_as_sf(res$hex_combined), col = "black", size = 0.05)
#' 
#' 
#'   mesh <- fm_mesh_2d(
#'   loc = res$hex_combined,
#'   bnd = fm_extensions(cbind(0, 0), convex = c(5, 8)),
#'   max_edge = c(0.5, 1)
#'   )
#'   
#'     ggplot() + gg(bnd_outer[[2]], col="blue") + gg(mesh)
#'}
#'
#' @export
fm_hexagon_lattice_multi <- function(
    sf_list,
    edge_len,
    clip_to = NULL,
    return_order = c("input", "processed"),
    make_valid = TRUE,
    drop_empty = TRUE,
    check_crs = TRUE,
    verbose = TRUE
) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  return_order <- match.arg(return_order)
  
  # checks
  if (!is.list(sf_list) || length(sf_list) == 0) {
    stop("`sf_list` must be a non-empty list of sf objects.")
  }
  
  if (!all(vapply(sf_list, inherits, logical(1), what = "sf"))) {
    stop("All elements of `sf_list` must be sf objects.")
  }
  
  if (length(edge_len) == 1) {
    edge_len <- rep(edge_len, length(sf_list))
  }
  
  if (length(edge_len) != length(sf_list)) {
    stop("`edge_len` must have length 1 or length equal to `sf_list`.")
  }
  
  if (is.null(names(sf_list))) {
    names(sf_list) <- paste0("layer_", seq_along(sf_list))
  } else {
    bad_names <- is.na(names(sf_list)) | names(sf_list) == ""
    names(sf_list)[bad_names] <- paste0("layer_", which(bad_names))
  }
  
  original_names <- names(sf_list)
  
  # CRS check
  if (check_crs) {
    crs_vec <- lapply(sf_list, sf::st_crs)
    crs_txt <- vapply(crs_vec, function(x) x$wkt %||% NA_character_, character(1))
    
    if (length(unique(crs_txt)) != 1) {
      stop("All sf objects in `sf_list` must have the same CRS.")
    }
    
    if (!is.null(clip_to)) {
      if (!inherits(clip_to, "sf")) {
        stop("`clip_to` must be an sf object or NULL.")
      }
      if (!identical(sf::st_crs(sf_list[[1]]), sf::st_crs(clip_to))) {
        stop("`clip_to` must have the same CRS as the sf objects.")
      }
    }
  }
  
  # validity
  if (make_valid) {
    sf_list <- lapply(sf_list, sf::st_make_valid)
    if (!is.null(clip_to)) {
      clip_to <- sf::st_make_valid(clip_to)
    }
  }
  
  # dissolve each layer
  bnds <- lapply(sf_list, function(x) {
    dplyr::summarise(x, do_union = TRUE)
  })
  
  if (make_valid) {
    bnds <- lapply(bnds, sf::st_make_valid)
  }
  
  # compute dissolved areas and sort smallest -> largest
  areas <- vapply(bnds, function(x) as.numeric(sf::st_area(x)), numeric(1))
  ord <- order(areas, decreasing = FALSE)
  
  bnds_proc <- bnds[ord]
  edge_len_proc <- edge_len[ord]
  areas_proc <- areas[ord]
  processed_names <- names(bnds_proc)
  
  # overlap matrix in processed order
  n <- length(bnds_proc)
  bnds_sf <- do.call(rbind, bnds_proc)
  
  overlap_matrix <- matrix(
    FALSE,
    nrow = n,
    ncol = n,
    dimnames = list(processed_names, processed_names)
  )
  
  for (i in seq_len(n)) {
    hit <- sf::st_intersects(bnds_proc[[i]], bnds_sf, sparse = FALSE)
    overlap_matrix[i, ] <- as.logical(hit[1, ])
    overlap_matrix[i, i] <- FALSE
  }
  
  # sequentially assign coverage
  cleaned_proc <- vector("list", n)
  names(cleaned_proc) <- processed_names
  
  claimed <- NULL
  
  for (i in seq_len(n)) {
    current <- bnds_proc[[i]]
    
    cleaned_i <- if (is.null(claimed)) {
      current
    } else {
      sf::st_difference(current, claimed)
    }
    
    if (make_valid) {
      cleaned_i <- sf::st_make_valid(cleaned_i)
    }
    
    cleaned_proc[[i]] <- cleaned_i
    
    geom_i <- sf::st_geometry(cleaned_i)
    if (!all(sf::st_is_empty(geom_i))) {
      claimed <- if (is.null(claimed)) {
        sf::st_union(geom_i)
      } else {
        sf::st_union(claimed, sf::st_union(geom_i))
      }
    }
  }
  
  # clip if requested
  if (!is.null(clip_to)) {
    cleaned_proc <- lapply(cleaned_proc, function(x) {
      sf::st_intersection(x, clip_to)
    })
  }
  
  # drop empties
  keep <- !vapply(cleaned_proc, function(x) {
    all(sf::st_is_empty(sf::st_geometry(x)))
  }, logical(1))
  
  if (drop_empty) {
    cleaned_proc <- cleaned_proc[keep]
    edge_len_proc <- edge_len_proc[keep]
    areas_proc <- areas_proc[keep]
  }
  
  # hexagon lattice
  hex_proc <- Map(
    function(bnd, e) fm_hexagon_lattice(bnd = bnd, edge_len = e),
    cleaned_proc,
    edge_len_proc
  )
  
  hex_combined <- if (length(hex_proc) > 0) do.call(c, hex_proc) else NULL
  
  # return order
  if (return_order == "input") {
    cleaned_names <- names(cleaned_proc)
    idx <- match(original_names, cleaned_names)
    idx <- idx[!is.na(idx)]
    
    cleaned <- cleaned_proc[idx]
    hex <- hex_proc[idx]
  } else {
    cleaned <- cleaned_proc
    hex <- hex_proc
  }
  
  if (verbose) {
    message("Processed ", length(sf_list), " layers.")
    message("Internal processing order: ", paste(processed_names, collapse = " -> "))
    message("Returned ", length(cleaned), " cleaned layers.")
    message("Any overlaps found: ", any(overlap_matrix))
  }
  
  list(
    overlap_matrix = overlap_matrix,
    areas = stats::setNames(areas_proc, names(cleaned_proc)),
    processed_names = processed_names,
    cleaned = cleaned,
    hex = hex,
    hex_combined = hex_combined
  )
}


# example: all overlapped -----------------------------------------------------------------

if(FALSE){
  
  bnd_outer <- lapply(fm_extensions(cbind(0, 0), convex = c(3, 5)), st_as_sf)
  bnd_inner <- lapply(fm_extensions(cbind(0, 0), convex = c(1, 1.5)), st_as_sf)
  
  res <- fm_hexagon_lattice_multi(
    sf_list = list(
      bnd_outer2 = bnd_outer[[2]],
      bnd_inner1 = bnd_inner[[1]],
      bnd_outer1 = bnd_outer[[1]],
      bnd_inner2 = bnd_inner[[2]]
    ),
    edge_len = c(0.2, 0.4, 0.4, 0.1) 
    # edge_len = c(0.2, 0.5, 0.5, 0.1) # slightly off for the mesh
    )
  
  ggplot() + 
    gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
    gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
    gg(st_as_sf(res$hex_combined), col = "black", size = 0.05)
  
  mesh <- fm_mesh_2d(
    loc = res$hex_combined,
    bnd = st_as_sfc(bnd_outer[[2]]),
    max_edge = c(0.5, 1)
  )
  
  ggplot() +
    gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
    gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
    gg(mesh)
  
  
  mesh <- fm_mesh_2d(
    loc = res$hex_combined,
    boundary = fm_extensions(cbind(0, 0), convex = c(5, 8)),
    max.edge = c(0.5,1)
  )
  
  ggplot() + 
    gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
    gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
    gg(mesh)
  

}


# example: partially overlapped ---------------------------------------------


if(FALSE){
  
  bnd_outer <- lapply(fm_extensions(cbind(0, 0), convex = c(3, 5)), st_as_sf)
  bnd_inner <- lapply(fm_extensions(cbind(4, 4), convex = c(1, 1.5)), st_as_sf)
  
  res <- fm_hexagon_lattice_multi(
    sf_list = list(
      bnd_outer1 = bnd_outer[[1]],
      bnd_outer2 = bnd_outer[[2]],
      bnd_inner1 = bnd_inner[[1]],
      bnd_inner2 = bnd_inner[[2]]
    ),
    edge_len = c(0.2, 0.5, 0.5, 0.1) 
    # * edge_len_gb
  )
  
  ggplot() + 
    gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
    gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
    gg(st_as_sf(res$hex_combined), col = "black", size = 0.05)
  
  mesh <- fm_mesh_2d(
    loc = res$hex_combined,
    bnd = bnd_outer[[2]],
    max_edge = 0.5
  )
  
  ggplot() + 
    gg(bnd_outer[[2]], col="blue") +
    gg(bnd_inner[[2]], col="yellow") +
    gg(mesh)
}


# example: spatially varying mesh -----------------------------------------
#   https://webhomes.maths.ed.ac.uk/~flindgre/posts/2018-07-22-spatially-varying-mesh-quality/
# TODO may have to tune the parameters to make them look nicer 
qual_loc <- function(loc) {
  pmax(0.05, (loc[, 1] * 2 + loc[, 2]) / 16)
}

qual_bnd <- function(loc) {
  rep(Inf, nrow(loc))
}

bnd <- fm_nonconvex_hull_inla(sf::st_coordinates(res$hex_combined), convex = 2, concave = 10)

mesh1 <- fm_rcdt_2d(
  loc = res$hex_combined,
  boundary = bnd,
  refine = list(
    max.edge = Inf
  ))

ggplot() + 
  gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
  gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
  gg(mesh1)

mesh2 <- fm_rcdt_2d(
  loc = res$hex_combined,
  boundary = bnd,
  refine = list(
    max.edge = .5,
    max.n.strict = 5000
  )
)

ggplot() + 
  gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
  gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
  gg(mesh2)

mesh3 <- fm_rcdt_2d(
  loc = res$hex_combined,
  boundary = bnd,
  refine = list(
    max.edge = Inf,
    max.n.strict = 5000
  ),
  quality.spec = list(
    loc = qual_loc(sf::st_coordinates(res$hex_combined)),
    segm = qual_loc(bnd$loc)
  )
)

ggplot() + 
  gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
  gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
  gg(mesh3)

mesh4 <- fm_rcdt_2d(
  loc = res$hex_combined,
  boundary = bnd,
  refine = list(
    max.edge = Inf,
    max.n.strict = 5000),
  quality.spec = list(
    loc = qual_loc(sf::st_coordinates(res$hex_combined)),
    segm = qual_bnd(bnd$loc)
  )
)

ggplot() + 
  gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
  gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
  gg(mesh4)

qual_bnd <- function(loc) {
  pmax(0.1, 1 - abs(loc[, 2] / 10)^2)
}
mesh5 <- fm_rcdt_2d(
  loc = res$hex_combined,
  boundary = bnd,
  refine = list(
    max.edge = Inf,
    max.n.strict = 5000),
  quality.spec = list(
    loc = qual_loc(sf::st_coordinates(res$hex_combined)),
    segm = qual_bnd(bnd$loc)
  )
)

ggplot() + 
  gg(bnd_outer[[2]], col="blue") + gg(bnd_outer[[1]], col = "red") + 
  gg(bnd_inner[[1]], col = "green") + gg(bnd_inner[[2]], col="yellow") + 
  gg(mesh5)
