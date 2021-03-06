import re
from collections import OrderedDict

from pyproj.compat import cstrencode, pystrdecode
from pyproj._datadir cimport get_pyproj_context
from pyproj.exceptions import CRSError

cdef cstrdecode(const char *instring):
    if instring != NULL:
        return pystrdecode(instring)
    return None

cdef decode_or_undefined(const char* instring):
    pystr = cstrdecode(instring)
    if pystr is None:
        return "undefined"
    return pystr

def is_wkt(proj_string):
    """
    Check if the input projection string is in the Well-Known Text format.

    Parameters
    ----------
    proj_string: str
        The projection string.

    Returns
    -------
    bool: True if the string is in the Well-Known Text format
    """
    tmp_string = cstrencode(proj_string)
    return proj_context_guess_wkt_dialect(NULL, tmp_string) != PJ_GUESSED_NOT_WKT


cdef _to_wkt(PJ_CONTEXT* projctx, PJ* projobj, version="WKT2_2018", pretty=False):
    """
    Convert a PJ object to a wkt string.

    Parameters
    ----------
    projctx: PJ_CONTEXT*
    projobj: PJ*
    wkt_out_type: PJ_WKT_TYPE
    pretty: bool

    Return
    ------
    str or None
    """
    # get the output WKT format
    supported_wkt_types = {
        "WKT2_2015": PJ_WKT2_2015,
        "WKT2_2015_SIMPLIFIED": PJ_WKT2_2015_SIMPLIFIED,
        "WKT2_2018": PJ_WKT2_2018,
        "WKT2_2018_SIMPLIFIED": PJ_WKT2_2018_SIMPLIFIED,
        "WKT1_GDAL": PJ_WKT1_GDAL,
        "WKT1_ESRI": PJ_WKT1_ESRI
    }
    cdef PJ_WKT_TYPE wkt_out_type
    try:
        wkt_out_type = supported_wkt_types[version.upper()]
    except KeyError:
        raise ValueError(
            "Invalid version supplied '{}'. "
            "Only {} are supported."
            .format(version, tuple(supported_wkt_types)))


    cdef const char* options_wkt[2]
    multiline = b"MULTILINE=NO"
    if pretty:
        multiline = b"MULTILINE=YES"
    options_wkt[0] = multiline
    options_wkt[1] = NULL
    cdef const char* proj_string
    proj_string = proj_as_wkt(
        projctx,
        projobj,
        wkt_out_type,
        options_wkt)
    return cstrdecode(proj_string)


cdef _to_proj4(PJ_CONTEXT* projctx, PJ* projobj, version=4):
    """
    Convert the projection to a PROJ.4 string.

    Parameters
    ----------
    version: int
        The version of the PROJ.4 output. Default is 4.

    Returns
    -------
    str: The PROJ.4 string.
    """
    # get the output PROJ.4 format
    supported_prj_types = {
        4: PJ_PROJ_4,
        5: PJ_PROJ_5,
    }
    cdef PJ_PROJ_STRING_TYPE proj_out_type
    try:
        proj_out_type = supported_prj_types[version]
    except KeyError:
        raise ValueError(
            "Invalid version supplied '{}'. "
            "Only {} are supported."
            .format(version, tuple(supported_prj_types)))

    # convert projection to string
    cdef const char* proj_string
    proj_string = proj_as_proj_string(
        projctx,
        projobj,
        proj_out_type,
        NULL)
    return cstrdecode(proj_string)


cdef PJ* _from_authority(
    auth_name, code, PJ_CATEGORY category, int use_proj_alternative_grid_names=False
):
    b_auth_name = cstrencode(auth_name)
    cdef char *c_auth_name = b_auth_name
    b_code = cstrencode(str(code))
    cdef char *c_code = b_code
    return proj_create_from_database(
        get_pyproj_context(),
        c_auth_name,
        c_code,
        category,
        use_proj_alternative_grid_names,
        NULL
    )

cdef class Axis:
    """
    Coordinate System Axis

    Attributes
    ----------
    name: str
    abbrev: str
    direction: str
    unit_conversion_factor: float
    unit_name: str
    unit_auth_code: str
    unit_code: str

    """
    def __cinit__(self):
        self.name = "undefined"
        self.abbrev = "undefined"
        self.direction = "undefined"
        self.unit_conversion_factor = float("NaN")
        self.unit_name = "undefined"
        self.unit_auth_code = "undefined"
        self.unit_code = "undefined"

    def __str__(self):
        return "{direction}: {name} [{unit_auth_code}:{unit_code}] ({unit_name})".format(
            name=self.name,
            direction=self.direction,
            unit_name=self.unit_name,
            unit_auth_code=self.unit_auth_code,
            unit_code=self.unit_code,
        )

    def __repr__(self):
        return ("Axis(name={name}, abbrev={abbrev}, direction={direction}, "
                "unit_auth_code={unit_auth_code}, unit_code={unit_code}, "
                "unit_name={unit_name})").format(
            name=self.name,
            abbrev=self.abbrev,
            direction=self.direction,
            unit_name=self.unit_name,
            unit_auth_code=self.unit_auth_code,
            unit_code=self.unit_code,
        )

    @staticmethod
    cdef create(PJ_CONTEXT* projcontext, PJ* projobj, int index):
        cdef Axis axis_info = Axis()
        cdef const char * name = NULL
        cdef const char * abbrev = NULL
        cdef const char * direction = NULL
        cdef const char * unit_name = NULL
        cdef const char * unit_auth_code = NULL
        cdef const char * unit_code = NULL
        if not proj_cs_get_axis_info(
                projcontext,
                projobj,
                index,
                &name,
                &abbrev,
                &direction,
                &axis_info.unit_conversion_factor,
                &unit_name,
                &unit_auth_code,
                &unit_code):
            return None
        axis_info.name = decode_or_undefined(name)
        axis_info.abbrev = decode_or_undefined(abbrev)
        axis_info.direction = decode_or_undefined(direction)
        axis_info.unit_name = decode_or_undefined(unit_name)
        axis_info.unit_auth_code = decode_or_undefined(unit_auth_code)
        axis_info.unit_code = decode_or_undefined(unit_code)
        return axis_info


cdef class AreaOfUse:
    """
    Area of Use for CRS

    Attributes
    ----------
    west: float
        West bound of area of use.
    south: float
        South bound of area of use.
    east: float
        East bound of area of use.
    north: float
        North bound of area of use.
    name: str
        Name of area of use.

    """
    def __cinit__(self):
        self.west = float("NaN")
        self.south = float("NaN")
        self.east = float("NaN")
        self.north = float("NaN")
        self.name = "undefined"

    def __str__(self):
        return "- name: {name}\n" \
               "- bounds: {bounds}".format(
            name=self.name, bounds=self.bounds)

    def __repr__(self):
        return ("AreaOfUse(name={name}, west={west}, south={south},"
                " east={east}, north={north})").format(
            name=self.name,
            west=self.west,
            south=self.south,
            east=self.east,
            north=self.north
        )

    @staticmethod
    cdef create(PJ_CONTEXT* projcontext, PJ* projobj):
        cdef AreaOfUse area_of_use = AreaOfUse()
        cdef const char * area_name = NULL
        if not proj_get_area_of_use(
                projcontext,
                projobj,
                &area_of_use.west,
                &area_of_use.south,
                &area_of_use.east,
                &area_of_use.north,
                &area_name):
            return None
        area_of_use.name = decode_or_undefined(area_name)
        return area_of_use

    @property
    def bounds(self):
        return self.west, self.south, self.east, self.north


cdef class Base:
    def __cinit__(self):
        self.projobj = NULL
        self.projctx = get_pyproj_context()
        self.name = "undefined"

    def __dealloc__(self):
        """destroy projection definition"""
        if self.projobj != NULL:
            proj_destroy(self.projobj)
        if self.projctx != NULL:
            proj_context_destroy(self.projctx)

    def _set_name(self):
        """
        Set the name of the PJ
        """
        # get proj information
        cdef const char* proj_name = proj_get_name(self.projobj)
        self.name = decode_or_undefined(proj_name)

    def to_wkt(self, version="WKT2_2018", pretty=False):
        """
        Convert the projection to a WKT string.

        Version options:
          - WKT2_2015
          - WKT2_2015_SIMPLIFIED
          - WKT2_2018
          - WKT2_2018_SIMPLIFIED
          - WKT1_GDAL
          - WKT1_ESRI


        Parameters
        ----------
        version: str
            The version of the WKT output. Default is WKT2_2018.
        pretty: bool
            If True, it will set the output to be a multiline string. Defaults to False.
 
        Returns
        -------
        str: The WKT string.
        """
        return _to_wkt(self.projctx, self.projobj, version, pretty=pretty)

    def __str__(self):
        return self.name

    def __repr__(self):
        return self.to_wkt(pretty=True)

    def is_exact_same(self, Base other):
        """Compares projections to see if they are exactly the same."""
        return proj_is_equivalent_to(
            self.projobj, other.projobj, PJ_COMP_STRICT) == 1

    def __eq__(self, Base other):
        """Compares projections to see if they are equivalent."""
        return proj_is_equivalent_to(
            self.projobj, other.projobj, PJ_COMP_EQUIVALENT) == 1


_COORD_SYSTEM_TYPE_MAP = {
    PJ_CS_TYPE_UNKNOWN: "unknown",
    PJ_CS_TYPE_CARTESIAN: "cartesian",
    PJ_CS_TYPE_ELLIPSOIDAL: "ellipsoidal",
    PJ_CS_TYPE_VERTICAL: "vertical",
    PJ_CS_TYPE_SPHERICAL: "spherical",
    PJ_CS_TYPE_ORDINAL: "ordinal",
    PJ_CS_TYPE_PARAMETRIC: "parametric",
    PJ_CS_TYPE_DATETIMETEMPORAL: "datetimetemporal",
    PJ_CS_TYPE_TEMPORALCOUNT: "temporalcount",
    PJ_CS_TYPE_TEMPORALMEASURE: "temporalmeasure",
}

cdef class CoordinateSystem(Base):
    """
    Coordinate System for CRS

    Attributes
    ----------
    name: str
        The name of the coordinate system.

    """
    def __cinit__(self):
        self._axis_list = None

    @staticmethod
    cdef create(PJ* coord_system_pj):
        cdef CoordinateSystem coord_system = CoordinateSystem()
        coord_system.projobj = coord_system_pj
        cdef PJ_COORDINATE_SYSTEM_TYPE cs_type = proj_cs_get_type(
            coord_system.projctx,
            coord_system.projobj,
        )
        try:
            coord_system.name = _COORD_SYSTEM_TYPE_MAP[cs_type]
        except KeyError:
            raise CRSError("Not a coordinate system.")
        return coord_system

    @property
    def axis_list(self):
        """
        Returns
        -------
        list[Axis]: The Axis list for the coordinate system.
        """
        if self._axis_list is not None:
            return self._axis_list
        self._axis_list = []
        cdef int num_axes = 0
        num_axes = proj_cs_get_axis_count(
            self.projctx,
            self.projobj
        )
        for axis_idx from 0 <= axis_idx < num_axes:
            self._axis_list.append(
                Axis.create(
                    self.projctx,
                    self.projobj,
                    axis_idx
                )
            )
        return self._axis_list


cdef class Ellipsoid(Base):
    """
    Ellipsoid for CRS

    Attributes
    ----------
    name: str
        The name of the ellipsoid.
    is_semi_minor_computed: int
        1 if True, 0 if False
    ellipsoid_loaded: bool
        True if it is loaded without errors.

    """
    def __cinit__(self):
        # load in ellipsoid information if applicable
        self._semi_major_metre = float("NaN")
        self._semi_minor_metre = float("NaN")
        self.is_semi_minor_computed = False
        self._inv_flattening = float("NaN")
        self.ellipsoid_loaded = False

    @staticmethod
    cdef create(PJ* ellipsoid_pj):
        cdef Ellipsoid ellips = Ellipsoid()
        ellips.projobj = ellipsoid_pj
        cdef int is_semi_minor_computed = 0
        try:
            proj_ellipsoid_get_parameters(
                ellips.projctx,
                ellips.projobj,
                &ellips._semi_major_metre,
                &ellips._semi_minor_metre,
                &is_semi_minor_computed,
                &ellips._inv_flattening)
            ellips.ellipsoid_loaded = True
            ellips.is_semi_minor_computed = is_semi_minor_computed == 1
        except Exception:
            pass
        ellips._set_name()
        return ellips

    @staticmethod
    def from_authority(auth_name, code):
        """
        Create an Ellipsoid from an authority code.

        Parameters
        ----------
        auth_name: str
            Name ot the authority.
        code: str or int
            The code used by the authority.

        Returns
        -------
        Ellipsoid
        """
        cdef PJ* ellipsoid_pj = _from_authority(
            auth_name,
            code,
            PJ_CATEGORY_ELLIPSOID,
        )
        if ellipsoid_pj == NULL:
            return None
        return Ellipsoid.create(ellipsoid_pj)

    @staticmethod
    def from_epsg(code):
        """
        Create an Ellipsoid from an EPSG code.

        Parameters
        ----------
        code: str or int
            The code used by the EPSG.

        Returns
        -------
        Ellipsoid
        """
        return Ellipsoid.from_authority("EPSG", code)

    @property
    def semi_major_metre(self):
        """
        The ellipsoid semi major metre.

        Returns
        -------
        float or None: The semi major metre if the projection is an ellipsoid.
        """
        if self.ellipsoid_loaded:
            return self._semi_major_metre
        return float("NaN")

    @property
    def semi_minor_metre(self):
        """
        The ellipsoid semi minor metre.

        Returns
        -------
        float or None: The semi minor metre if the projection is an ellipsoid
            and the value was com
            puted.
        """
        if self.ellipsoid_loaded and self.is_semi_minor_computed:
            return self._semi_minor_metre
        return float("NaN")

    @property
    def inverse_flattening(self):
        """
        The ellipsoid inverse flattening.

        Returns
        -------
        float or None: The inverse flattening if the projection is an ellipsoid.
        """
        if self.ellipsoid_loaded:
            return self._inv_flattening
        return float("NaN")


cdef class PrimeMeridian(Base):
    """
    Prime Meridian for CRS

    Attributes
    ----------
    name: str
        The name of the prime meridian.
    unit_name: str
        The unit name for the prime meridian.

    """
    def __cinit__(self):
        self.unit_name = None

    @staticmethod
    cdef create(PJ* prime_meridian_pj):
        cdef PrimeMeridian prime_meridian = PrimeMeridian()
        prime_meridian.projobj = prime_meridian_pj
        cdef const char * unit_name
        proj_prime_meridian_get_parameters(
            prime_meridian.projctx,
            prime_meridian.projobj,
            &prime_meridian.longitude,
            &prime_meridian.unit_conversion_factor,
            &unit_name,
        )
        prime_meridian.unit_name = decode_or_undefined(unit_name)
        prime_meridian._set_name()
        return prime_meridian

    @staticmethod
    def from_authority(auth_name, code):
        """
        Create a PrimeMeridian from an authority code.

        Parameters
        ----------
        auth_name: str
            Name ot the authority.
        code: str or int
            The code used by the authority.

        Returns
        -------
        PrimeMeridian
        """
        cdef PJ* prime_meridian_pj = _from_authority(
            auth_name,
            code,
            PJ_CATEGORY_PRIME_MERIDIAN,
        )
        if prime_meridian_pj == NULL:
            return None
        return PrimeMeridian.create(prime_meridian_pj)

    @staticmethod
    def from_epsg(code):
        """
        Create a PrimeMeridian from an EPSG code.

        Parameters
        ----------
        code: str or int
            The code used by EPSG.

        Returns
        -------
        PrimeMeridian
        """
        return PrimeMeridian.from_authority("EPSG", code)



cdef class Datum(Base):
    """
    Datum for CRS. If it is a compound CRS it is the horizontal datum.

    Attributes
    ----------
    name: str
        The name of the datum.

    """
    def __cinit__(self):
        self._ellipsoid = None
        self._prime_meridian = None

    @staticmethod
    cdef create(PJ* datum_pj):
        cdef Datum datum = Datum()
        datum.projobj = datum_pj
        datum._set_name()
        return datum

    @staticmethod
    def from_authority(auth_name, code):
        """
        Create a Datum from an authority code.

        Parameters
        ----------
        auth_name: str
            Name ot the authority.
        code: str or int
            The code used by the authority.

        Returns
        -------
        Datum
        """
        cdef PJ* datum_pj = _from_authority(
            auth_name,
            code,
            PJ_CATEGORY_DATUM,
        )
        if datum_pj == NULL:
            return None
        return Datum.create(datum_pj)

    @staticmethod
    def from_epsg(code):
        """
        Create a Datum from an EPSG code.

        Parameters
        ----------
        code: str or int
            The code used by EPSG.

        Returns
        -------
        Datum
        """
        return Datum.from_authority("EPSG", code)

    @property
    def ellipsoid(self):
        """
        Returns
        -------
        Ellipsoid: The ellipsoid object with associated attributes.
        """
        if self._ellipsoid is not None:
            return None if self._ellipsoid is False else self._ellipsoid
        cdef PJ* ellipsoid_pj = proj_get_ellipsoid(self.projctx, self.projobj)
        if ellipsoid_pj == NULL:
            self._ellipsoid = False
            return None
        self._ellipsoid = Ellipsoid.create(ellipsoid_pj)
        return self._ellipsoid

    @property
    def prime_meridian(self):
        """
        Returns
        -------
        PrimeMeridian: The CRS prime meridian object with associated attributes.
        """
        if self._prime_meridian is not None:
            return None if self._prime_meridian is False else self._prime_meridian
        cdef PJ* prime_meridian_pj = proj_get_prime_meridian(self.projctx, self.projobj)
        if prime_meridian_pj == NULL:
            self._prime_meridian = False
            return None
        self._prime_meridian = PrimeMeridian.create(prime_meridian_pj)
        return self._prime_meridian


cdef class Param:
    """
    Coordinate operation parameter.

    Attributes
    ----------
    name: str
        The name of the parameter.
    auth_name: str
        The authority name of the parameter (i.e. EPSG).
    code: str
        The code of the parameter (i.e. 9807).
    value: str or double
        The value of the parameter.
    unit_conversion_factor: double
        The factor to convert to meters.
    unit_name: str
        The name of the unit.
    unit_auth_name: str
        The authority name of the unit (i.e. EPSG).
    unit_code: str
        The code of the unit (i.e. 9807).
    unit_category: str
        The category of the unit (“unknown”, “none”, “linear”, 
        “angular”, “scale”, “time” or “parametric”).

    """
    def __cinit__(self):
        self.name = "undefined"
        self.auth_name = "undefined"
        self.code = "undefined"
        self.value = "undefined"
        self.unit_conversion_factor = float("nan")
        self.unit_name = "undefined"
        self.unit_auth_name = "undefined"
        self.unit_code = "undefined"
        self.unit_category = "undefined"

    @staticmethod
    cdef create(PJ_CONTEXT* projcontext, PJ* projobj, int param_idx):
        cdef Param param = Param()
        cdef char *out_name
        cdef char *out_auth_name
        cdef char *out_code
        cdef char *out_value
        cdef char *out_value_string
        cdef char *out_unit_name
        cdef char *out_unit_auth_name
        cdef char *out_unit_code
        cdef char *out_unit_category
        cdef double value_double
        proj_coordoperation_get_param(
            projcontext,
            projobj,
            param_idx,
            &out_name,
            &out_auth_name,
            &out_code,
            &value_double,
            &out_value_string,
            &param.unit_conversion_factor,
            &out_unit_name,
            &out_unit_auth_name,
            &out_unit_code,
            &out_unit_category
        )
        param.name = decode_or_undefined(out_name)
        param.auth_name = decode_or_undefined(out_auth_name)
        param.code = decode_or_undefined(out_code)
        param.unit_name = decode_or_undefined(out_unit_name)
        param.unit_auth_name = decode_or_undefined(out_unit_auth_name)
        param.unit_code = decode_or_undefined(out_unit_code)
        param.unit_category = decode_or_undefined(out_unit_category)
        value_string = cstrdecode(out_value_string)
        param.value = value_double if value_string is None else value_string
        return param

    def __str__(self):
        return "{auth_name}:{auth_code}".format(self.auth_name, self.auth_code)

    def __repr__(self):
        return ("Param(name={name}, auth_name={auth_name}, code={code}, "
                "value={value}, unit_name={unit_name}, unit_auth_name={unit_auth_name}, "
                "unit_code={unit_code}, unit_category={unit_category})").format(
            name=self.name,
            auth_name=self.auth_name,
            code=self.code,
            value=self.value,
            unit_name=self.unit_name,
            unit_auth_name=self.unit_auth_name,
            unit_code=self.unit_code,
            unit_category=self.unit_category,
        )



cdef class Grid:
    """
    Coordinate operation grid.

    Attributes
    ----------
    short_name: str
        The short name of the grid.
    full_name: str
        The full name of the grid.
    package_name: str
        The the package name where the grid might be found.
    url: str
        The grid URL or the package URL where the grid might be found.
    direct_download: int
        If 1, *url* can be downloaded directly.
    open_license: int
        If 1, the grid is released with an open license.
    available: int
        If 1, the grid is available at runtime. 

    """
    def __cinit__(self):
        self.short_name = "undefined"
        self.full_name = "undefined"
        self.package_name = "undefined"
        self.url = "undefined"
        self.direct_download = False
        self.open_license = False
        self.available = False

    @staticmethod
    cdef create(PJ_CONTEXT* projcontext, PJ* projobj, int grid_idx):
        cdef Grid grid = Grid()
        cdef char *out_short_name
        cdef char *out_full_name
        cdef char *out_package_name
        cdef char *out_url
        cdef int direct_download = 0
        cdef int open_license = 0
        cdef int available = 0
        proj_coordoperation_get_grid_used(
            projcontext,
            projobj,
            grid_idx,
            &out_short_name,
            &out_full_name,
            &out_package_name,
            &out_url,
            &direct_download,
            &open_license,
            &available
        )
        grid.short_name = decode_or_undefined(out_short_name)
        grid.full_name = decode_or_undefined(out_full_name)
        grid.package_name = decode_or_undefined(out_package_name)
        grid.url = decode_or_undefined(out_url)
        grid.direct_download = direct_download == 1
        grid.open_license = open_license == 1
        grid.available = available == 1
        return grid

    def __str__(self):
        return self.full_name

    def __repr__(self):
        return ("Grid(short_name={short_name}, full_name={full_name}, package_name={package_name}, "
                "url={url}, direct_download={direct_download}, open_license={open_license}, "
                "available={available})").format(
            short_name=self.short_name,
            full_name=self.full_name,
            package_name=self.package_name,
            url=self.url,
            direct_download=self.direct_download,
            open_license=self.open_license,
            available=self.available
        )


cdef class CoordinateOperation(Base):
    """
    Coordinate operation for CRS.

    Attributes
    ----------
    name: str
        The name of the method(projection) with authority information.
    method_name: str
        The method (projection) name.
    method_auth_name: str
        The method authority name.
    method_code: str
        The method code.
    is_instantiable: int
        If 1, a coordinate operation can be instantiated as a PROJ pipeline.
        This also checks that referenced grids are available. 
    has_ballpark_transformation: int
        If 1, the coordinate operation has a “ballpark” transformation, 
        that is a very approximate one, due to lack of more accurate transformations. 
    accuracy: float
        The accuracy (in metre) of a coordinate operation. 

    """
    def __cinit__(self):
        self._params = None
        self._grids = None
        self.method_name = "undefined"
        self.method_auth_name = "undefined"
        self.method_code = "undefined"
        self.is_instantiable = False
        self.has_ballpark_transformation = False
        self.accuracy = float("nan")
        self._towgs84 = None

    @staticmethod
    cdef create(PJ* coord_operation_pj):
        cdef CoordinateOperation coord_operation = CoordinateOperation()
        coord_operation.projobj = coord_operation_pj
        cdef char *out_method_name = NULL
        cdef char *out_method_auth_name = NULL
        cdef char *out_method_code = NULL
        proj_coordoperation_get_method_info(
            coord_operation.projctx,
            coord_operation.projobj,
            &out_method_name,
            &out_method_auth_name,
            &out_method_code
        )
        coord_operation._set_name()
        coord_operation.method_name = decode_or_undefined(out_method_name)
        coord_operation.method_auth_name = decode_or_undefined(out_method_auth_name)
        coord_operation.method_code = decode_or_undefined(out_method_code)
        coord_operation.accuracy = proj_coordoperation_get_accuracy(
            coord_operation.projctx,
            coord_operation.projobj
        )
        coord_operation.is_instantiable = proj_coordoperation_is_instantiable(
            coord_operation.projctx,
            coord_operation.projobj
        ) == 1
        coord_operation.has_ballpark_transformation = \
            proj_coordoperation_has_ballpark_transformation(
                coord_operation.projctx,
                coord_operation.projobj
            ) == 1

        return coord_operation

    @staticmethod
    def from_authority(auth_name, code, use_proj_alternative_grid_names=False):
        """
        Create a CoordinateOperation from an authority code.

        Parameters
        ----------
        auth_name: str
            Name ot the authority.
        code: str or int
            The code used by the authority.
        use_proj_alternative_grid_names: bool, optional
            Use the PROJ alternative grid names. Default is False.

        Returns
        -------
        CoordinateOperation
        """
        cdef PJ* coord_operation_pj = _from_authority(
            auth_name,
            code,
            PJ_CATEGORY_COORDINATE_OPERATION,
            use_proj_alternative_grid_names,
        )
        if coord_operation_pj == NULL:
            return None
        return CoordinateOperation.create(coord_operation_pj)

    @staticmethod
    def from_epsg(code, use_proj_alternative_grid_names=False):
        """
        Create a CoordinateOperation from an EPSG code.

        Parameters
        ----------
        code: str or int
            The code used by EPSG.
        use_proj_alternative_grid_names: bool, optional
            Use the PROJ alternative grid names. Default is False.

        Returns
        -------
        CoordinateOperation
        """
        return CoordinateOperation.from_authority(
            "EPSG", code, use_proj_alternative_grid_names
        )

    @property
    def params(self):
        """
        Returns
        -------
        list[Param]: The coordinate operation parameters.
        """
        if self._params is not None:
            return self._params
        self._params = []
        cdef int num_params = 0
        num_params = proj_coordoperation_get_param_count(
            self.projctx,
            self.projobj
        )
        for param_idx from 0 <= param_idx < num_params:
            self._params.append(
                Param.create(
                    self.projctx,
                    self.projobj,
                    param_idx
                )
            )
        return self._params

    @property
    def grids(self):
        """
        Returns
        -------
        list[Grid]: The coordinate operation grids.
        """
        if self._grids is not None:
            return self._grids
        self._grids = []
        cdef int num_grids = 0
        num_grids = proj_coordoperation_get_grid_used_count(
            self.projctx,
            self.projobj
        )
        for grid_idx from 0 <= grid_idx < num_grids:
            self._grids.append(
                Grid.create(
                    self.projctx,
                    self.projobj,
                    grid_idx
                )
            )
        return self._grids

    def to_proj4(self, version=5):
        """
        Convert the projection to a PROJ.4 string.

        Parameters
        ----------
        version: int
            The version of the PROJ.4 string. Default is 5.

        Returns
        -------
        str: The PROJ.4 string.
        """
        return _to_proj4(self.projctx, self.projobj, version)

    @property
    def towgs84(self):
        """
        Returns
        -------
        list(float): A list of 3 or 7 towgs84 values if they exist.
            Otherwise an empty list.
        """
        if self._towgs84 is not None:
            return self._towgs84
        towgs84_dict = OrderedDict(
            (
                ('X-axis translation', None), 
                ('Y-axis translation', None),
                ('Z-axis translation', None),
                ('X-axis rotation', None),
                ('Y-axis rotation', None),
                ('Z-axis rotation', None),
                ('Scale difference', None),
            )
        )
        for param in self.params:
            if param.name in towgs84_dict:
                towgs84_dict[param.name] = param.value
        self._towgs84 = [val for val in towgs84_dict.values() if val is not None]
        return self._towgs84
 
cdef class _CRS(Base):
    """
    The cython CRS class to be used as the base for the
    python CRS class.
    """
    def __cinit__(self):
        self._ellipsoid = None
        self._area_of_use = None
        self._prime_meridian = None
        self._datum = None
        self._sub_crs_list = None
        self._source_crs = None
        self._coordinate_system = None
        self._coordinate_operation = None

    def __init__(self, proj_string):
        # setup proj initialization string.
        if not is_wkt(proj_string) \
                and not re.match("^\w+:\d+$", proj_string.strip())\
                and "type=crs" not in proj_string:
            proj_string += " +type=crs"
        # initialize projection
        self.projobj = proj_create(self.projctx, cstrencode(proj_string))
        if self.projobj is NULL:
            raise CRSError(
                "Invalid projection: {}".format(pystrdecode(proj_string)))
        # make sure the input is a CRS
        if not proj_is_crs(self.projobj):
            raise CRSError("Input is not a CRS: {}".format(proj_string))
        # set proj information
        self.srs = pystrdecode(proj_string)
        self._type = proj_get_type(self.projobj)
        self._set_name()

    @property
    def axis_info(self):
        """
        Returns
        -------
        list[Axis]: The list of axis information.
        """
        return self.coordinate_system.axis_list if self.coordinate_system else []

    @property
    def area_of_use(self):
        """
        Returns
        -------
        AreaOfUse: The area of use object with associated attributes.
        """
        if self._area_of_use is not None:
            return self._area_of_use
        self._area_of_use = AreaOfUse.create(self.projctx, self.projobj)
        return self._area_of_use

    @property
    def ellipsoid(self):
        """
        Returns
        -------
        Ellipsoid: The ellipsoid object with associated attributes.
        """
        if self._ellipsoid is not None:
            return None if self._ellipsoid is False else self._ellipsoid
        cdef PJ* ellipsoid_pj = proj_get_ellipsoid(self.projctx, self.projobj)
        if ellipsoid_pj == NULL:
            self._ellipsoid = False
            return None
        self._ellipsoid = Ellipsoid.create(ellipsoid_pj)
        return self._ellipsoid

    @property
    def prime_meridian(self):
        """
        Returns
        -------
        PrimeMeridian: The CRS prime meridian object with associated attributes.
        """
        if self._prime_meridian is not None:
            return None if self._prime_meridian is True else self._prime_meridian
        cdef PJ* prime_meridian_pj = proj_get_prime_meridian(self.projctx, self.projobj)
        if prime_meridian_pj == NULL:
            self._prime_meridian = False
            return None
        self._prime_meridian = PrimeMeridian.create(prime_meridian_pj)
        return self._prime_meridian

    @property
    def datum(self):
        """
        Returns
        -------
        Datum: The datum.
        """
        if self._datum is not None:
            return None if self._datum is False else self._datum
        cdef PJ* datum_pj = proj_crs_get_datum(self.projctx, self.projobj)
        if datum_pj == NULL:
            datum_pj = proj_crs_get_horizontal_datum(self.projctx, self.projobj)
        if datum_pj == NULL:
            self._datum = False
            return None
        self._datum = Datum.create(datum_pj)
        return self._datum

    @property
    def coordinate_system(self):
        """
        Returns
        -------
        CoordinateSystem: The coordinate system.
        """
        if self._coordinate_system is not None:
            return None if self._coordinate_system is False else self._coordinate_system

        cdef PJ* coord_system_pj = proj_crs_get_coordinate_system(
            self.projctx,
            self.projobj
        )
        if coord_system_pj == NULL:
            self._coordinate_system = False
            return None

        self._coordinate_system = CoordinateSystem.create(coord_system_pj)
        return self._coordinate_system

    @property
    def coordinate_operation(self):
        """
        Returns
        -------
        CoordinateOperation: The coordinate operation.
        """
        if self._coordinate_operation is not None:
            return None if self._coordinate_operation is False else self._coordinate_operation
        cdef PJ* coord_pj = NULL
        coord_pj = proj_crs_get_coordoperation(
            self.projctx,
            self.projobj
        )
        if coord_pj == NULL:
            self._coordinate_operation = False
            return None
        self._coordinate_operation = CoordinateOperation.create(coord_pj)
        return self._coordinate_operation

    @property
    def source_crs(self):
        """
        Returns
        -------
        CRS: The source CRS.
        """
        if self._source_crs is not None:
            return None if self._source_crs is False else self._source_crs
        cdef PJ * projobj
        projobj = proj_get_source_crs(self.projctx, self.projobj)
        if projobj == NULL:
            self._source_crs = False
            return None
        try:
            self._source_crs = self.__class__(_to_wkt(self.projctx, projobj))
        finally:
            proj_destroy(projobj) # deallocate temp proj
        return self._source_crs

    @property
    def sub_crs_list(self):
        """
        If the CRS is a compound CRS, it will return a list of sub CRS objects.

        Returns
        -------
        list[CRS]

        """
        if self._sub_crs_list is not None:
            return self._sub_crs_list
        cdef int iii = 0
        cdef PJ * projobj = proj_crs_get_sub_crs(self.projctx, self.projobj, iii)
        self._sub_crs_list = []
        while projobj != NULL:
            try:
                self._sub_crs_list.append(self.__class__(_to_wkt(self.projctx, projobj)))
            finally:
                proj_destroy(projobj) # deallocate temp proj
            iii += 1
            projobj = proj_crs_get_sub_crs(self.projctx, self.projobj, iii)

        return self._sub_crs_list

    def to_proj4(self, version=4):
        """
        Convert the projection to a PROJ.4 string.

        Parameters
        ----------
        version: int
            The version of the PROJ.4 output. Default is 4.

        Returns
        -------
        str: The PROJ.4 string.
        """
        return _to_proj4(self.projctx, self.projobj, version)

    def to_geodetic(self):
        """

        Returns
        -------
        pyproj.CRS: The geographic (lat/lon) CRS from the current CRS.

        """
        cdef PJ * projobj
        projobj = proj_crs_get_geodetic_crs(self.projctx, self.projobj)
        if projobj == NULL:
            return None
        try:
            return self.__class__(_to_wkt(self.projctx, projobj))
        finally:
            proj_destroy(projobj) # deallocate temp proj

    def to_epsg(self, min_confidence=70):
        """
        Return the EPSG code best matching the projection.

        Parameters
        ----------
        min_confidence: int, optional
            A value between 0-100 where 100 is the most confident. Default is 70.

        Returns
        -------
        int or None: The best matching EPSG code matching the confidence level.
        """
        # get list of possible matching projections
        cdef PJ_OBJ_LIST *proj_list = NULL
        cdef int *out_confidence_list = NULL
        cdef int out_confidence = -9999
        cdef int num_proj_objects = -9999

        try:
            proj_list  = proj_identify(self.projctx,
                self.projobj,
                b"EPSG",
                NULL,
                &out_confidence_list
            )
            if proj_list != NULL:
                num_proj_objects = proj_list_get_count(proj_list)
            if out_confidence_list != NULL and num_proj_objects > 0:
                out_confidence = out_confidence_list[0]
        finally:
            if out_confidence_list != NULL:
                proj_int_list_destroy(out_confidence_list)

        # check to make sure that the projection found is valid
        if proj_list == NULL or num_proj_objects <= 0 or out_confidence < min_confidence:
            if proj_list != NULL:
                proj_list_destroy(proj_list)
            return None

        # retrieve the best matching projection
        cdef PJ* proj
        try:
            proj = proj_list_get(self.projctx, proj_list, 0)
        finally:
            proj_list_destroy(proj_list)
        if proj == NULL:
            return None

        # convert the matching projection to the EPSG code
        cdef const char* code
        try:
            code = proj_get_id_code(proj, 0)
            if code != NULL:
                return int(code)
        finally:
            proj_destroy(proj)

        return None

    @property
    def is_geographic(self):
        """
        Returns
        -------
        bool: True if projection in geographic (lon/lat) coordinates.
        """
        if self.sub_crs_list:
            sub_crs = self.sub_crs_list[0]
            if sub_crs.is_bound:
                is_geographic = sub_crs.source_crs.is_geographic
            else:
                is_geographic = sub_crs.is_geographic
        elif self.is_bound:
            is_geographic = self.source_crs.is_geographic
        else:
            is_geographic = self._type in (
                PJ_TYPE_GEOGRAPHIC_CRS,
                PJ_TYPE_GEOGRAPHIC_2D_CRS,
                PJ_TYPE_GEOGRAPHIC_3D_CRS
            )
        return is_geographic

    @property
    def is_projected(self):
        """
        Returns
        -------
        bool: True if projection is a projected CRS.
        """
        if self.sub_crs_list:
            sub_crs = self.sub_crs_list[0]
            if sub_crs.is_bound:
                is_projected = sub_crs.source_crs.is_projected
            else:
                is_projected = sub_crs.is_projected
        elif self.is_bound:
            is_projected = self.source_crs.is_projected
        else:
            is_projected = self._type == PJ_TYPE_PROJECTED_CRS
        return is_projected 

    @property
    def is_bound(self):
        """
        Returns
        -------
        bool: True if projection is a bound CRS.
        """
        return self._type == PJ_TYPE_BOUND_CRS

    @property
    def is_valid(self):
        """
        Returns
        -------
        bool: True if projection is a valid CRS.
        """
        return self._type != PJ_TYPE_UNKNOWN

    @property
    def is_geocentric(self):
        """
        Returns
        -------
        bool: True if projection in geocentric (x/y) coordinates
        """
        return self._type == PJ_TYPE_GEOCENTRIC_CRS
